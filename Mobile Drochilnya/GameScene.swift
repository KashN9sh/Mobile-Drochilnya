//
//  GameScene.swift
//  Mobile Drochilnya
//
//  Created by Roman on 13.09.2025.
//

import SpriteKit
import GameplayKit
import UIKit

struct PhysicsCategory {
    static let none: UInt32 = 0
    static let player: UInt32 = 1 << 0
    static let arrow: UInt32 = 1 << 1
    static let enemy: UInt32 = 1 << 2
    static let world: UInt32 = 1 << 3
}

private struct EnemyType {
    let name: String
    let color: SKColor
    let baseHP: Int
    let speed: CGFloat
    let weight: CGFloat
}

private enum PerkType: CaseIterable {
    case fireRate
    case extraArrow
    case critChance
    case critDamage
    case magnet
    case damage
}

class GameScene: SKScene, SKPhysicsContactDelegate {
    
    private var playerNode: SKSpriteNode!
    private var killsCount: Int = 0 {
        didSet { updateHUD() }
    }
    private var level: Int = 1 {
        didSet { updateHUD() }
    }
    private var coins: Int = 0 {
        didSet { updateHUD() }
    }
    
    // Tunable gameplay parameters
    private var arrowsPerShot: Int = 1
    private var fireInterval: TimeInterval = 0.9
    private var arrowSpeedPointsPerSecond: CGFloat = 900
    private var enemySpawnInterval: TimeInterval = 1.2
    private var enemySpeedPointsPerSecond: CGFloat = 120
    
    // Combat
    private var baseArrowDamage: Int = 1
    private var critChance: CGFloat = 0.15
    private var critMultiplier: CGFloat = 2.0
    
    // Loot
    private var coinMagnetRadius: CGFloat = 80
    private var coinFallSpeedPointsPerSecond: CGFloat = 220
    
    // Enemy variety
    private var enemyTypes: [EnemyType] = []
    private var isBossActive: Bool = false
    private weak var currentBossNode: SKSpriteNode?
    
    // Perks UI
    private var isPerkChoiceActive: Bool = false
    private var perkOverlay: SKNode?
    
    // Death/Restart
    private var isGameOver: Bool = false
    private var deathOverlay: SKNode?
    
    // HUD
    private var killsLabel: SKLabelNode!
    private var levelLabel: SKLabelNode!
    private var coinsLabel: SKLabelNode!
    
    // MARK: - Scene lifecycle
    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        
        physicsBody = SKPhysicsBody(edgeLoopFrom: frame)
        physicsBody?.categoryBitMask = PhysicsCategory.world
        physicsBody?.collisionBitMask = 0
        physicsBody?.contactTestBitMask = 0
        
        configureEnemyTypes()
        setupPlayer()
        setupHUD()
        startAutoFire()
        startEnemySpawns()
        updateHUD()
    }
    
    // MARK: - Setup
    private func setupPlayer() {
        let size = CGSize(width: 40, height: 40)
        let node = SKSpriteNode(color: .white, size: size)
        node.position = CGPoint(x: frame.midX, y: frame.minY + size.height * 1.5)
        node.zPosition = 10
        node.name = "player"
        
        let body = SKPhysicsBody(rectangleOf: size)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.player
        body.collisionBitMask = 0
        body.contactTestBitMask = PhysicsCategory.enemy
        node.physicsBody = body
        
        addChild(node)
        playerNode = node
    }
    
    private func setupHUD() {
        killsLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        killsLabel.horizontalAlignmentMode = .left
        killsLabel.verticalAlignmentMode = .top
        killsLabel.fontSize = 16
        killsLabel.fontColor = .white
        killsLabel.position = CGPoint(x: frame.minX + 16, y: frame.maxY - 16)
        killsLabel.zPosition = 100
        addChild(killsLabel)
        
        levelLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        levelLabel.horizontalAlignmentMode = .right
        levelLabel.verticalAlignmentMode = .top
        levelLabel.fontSize = 16
        levelLabel.fontColor = .white
        levelLabel.position = CGPoint(x: frame.maxX - 16, y: frame.maxY - 16)
        levelLabel.zPosition = 100
        addChild(levelLabel)
        
        coinsLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        coinsLabel.horizontalAlignmentMode = .center
        coinsLabel.verticalAlignmentMode = .top
        coinsLabel.fontSize = 16
        coinsLabel.fontColor = .systemYellow
        coinsLabel.position = CGPoint(x: frame.midX, y: frame.maxY - 16)
        coinsLabel.zPosition = 100
        addChild(coinsLabel)
    }
    
    private func updateHUD() {
        killsLabel?.text = "Kills: \(killsCount)"
        levelLabel?.text = "Lvl: \(level)"
        coinsLabel?.text = "\u{1F4B0} \(coins)"
    }
    
    private func configureEnemyTypes() {
        enemyTypes = [
            EnemyType(name: "grunt", color: .systemRed, baseHP: 3, speed: 120, weight: 1.0),
            EnemyType(name: "brute", color: .systemOrange, baseHP: 7, speed: 90, weight: 0.55),
            EnemyType(name: "swift", color: .systemPink, baseHP: 2, speed: 170, weight: 0.6),
        ]
    }
    
    // MARK: - Auto fire
    private func startAutoFire() {
        removeAction(forKey: "autoFire")
        let wait = SKAction.wait(forDuration: fireInterval)
        let fire = SKAction.run { [weak self] in
            self?.fireVolley()
        }
        run(SKAction.repeatForever(SKAction.sequence([fire, wait])), withKey: "autoFire")
    }
    
    private func fireVolley() {
        guard let playerNode else { return }
        if isPerkChoiceActive || isGameOver { return }
        let total = max(1, arrowsPerShot)
        let spread: CGFloat = total > 1 ? 0.6 : 0.0
        for i in 0..<total {
            let t = total == 1 ? 0.0 : (CGFloat(i) / CGFloat(total - 1) - 0.5)
            let angleOffset = spread * t
            spawnArrow(from: playerNode.position, angleOffset: angleOffset)
        }
    }
    
    private func spawnArrow(from origin: CGPoint, angleOffset: CGFloat) {
        let arrowSize = CGSize(width: 6, height: 18)
        let arrow = SKSpriteNode(color: .systemGreen, size: arrowSize)
        arrow.position = CGPoint(x: origin.x, y: origin.y + 28)
        arrow.zPosition = 5
        arrow.name = "arrow"
        
        let body = SKPhysicsBody(rectangleOf: arrowSize)
        body.isDynamic = true
        body.affectedByGravity = false
        body.allowsRotation = false
        body.categoryBitMask = PhysicsCategory.arrow
        body.collisionBitMask = 0
        body.contactTestBitMask = PhysicsCategory.enemy
        arrow.physicsBody = body
        
        addChild(arrow)
        
        let directionAngle = (.pi / 2.0) + angleOffset
        let dx = cos(directionAngle) * arrowSpeedPointsPerSecond
        let dy = sin(directionAngle) * arrowSpeedPointsPerSecond
        arrow.zRotation = directionAngle
        arrow.physicsBody?.velocity = CGVector(dx: dx, dy: dy)
        
        let lifetime: TimeInterval = 2.5
        arrow.run(SKAction.sequence([.wait(forDuration: lifetime), .removeFromParent()]))
    }
    
    // MARK: - Enemies
    private func startEnemySpawns() {
        removeAction(forKey: "spawnEnemies")
        let wait = SKAction.wait(forDuration: enemySpawnInterval)
        let spawn = SKAction.run { [weak self] in
            self?.spawnEnemy()
        }
        run(SKAction.repeatForever(SKAction.sequence([spawn, wait])), withKey: "spawnEnemies")
    }
    
    private func randomEnemyType() -> EnemyType {
        let totalWeight = enemyTypes.reduce(0) { $0 + $1.weight }
        var roll = CGFloat.random(in: 0...totalWeight)
        for type in enemyTypes {
            if roll < type.weight { return type }
            roll -= type.weight
        }
        return enemyTypes.first!
    }
    
    private func spawnEnemy() {
        if isPerkChoiceActive || isGameOver || isBossActive { return }
        let type = randomEnemyType()
        let size = CGSize(width: 32, height: 32)
        let enemy = SKSpriteNode(color: type.color, size: size)
        let minX = frame.minX + size.width / 2.0 + 8
        let maxX = frame.maxX - size.width / 2.0 - 8
        let x = CGFloat.random(in: minX...maxX)
        enemy.position = CGPoint(x: x, y: frame.maxY + size.height)
        enemy.zPosition = 5
        enemy.name = "enemy"
        
        let body = SKPhysicsBody(rectangleOf: size)
        body.isDynamic = true
        body.affectedByGravity = false
        body.allowsRotation = false
        body.categoryBitMask = PhysicsCategory.enemy
        body.collisionBitMask = 0
        body.contactTestBitMask = PhysicsCategory.arrow | PhysicsCategory.player
        enemy.physicsBody = body
        
        let hpScale = 1 + max(0, (level - 1)) / 3
        let initialHP = max(1, type.baseHP + hpScale)
        if enemy.userData == nil { enemy.userData = NSMutableDictionary() }
        enemy.userData?["hp"] = initialHP
        
        addChild(enemy)
        
        let distance = (enemy.position.y - (frame.minY - size.height))
        let duration = TimeInterval(distance / type.speed)
        let move = SKAction.moveTo(y: frame.minY - size.height, duration: duration)
        enemy.run(SKAction.sequence([move, .removeFromParent()]))
    }
    
    private func spawnBoss() {
        if isPerkChoiceActive || isGameOver || isBossActive { return }
        isBossActive = true
        removeAction(forKey: "spawnEnemies")
        
        let size = CGSize(width: 70, height: 70)
        let boss = SKSpriteNode(color: .purple, size: size)
        boss.position = CGPoint(x: frame.midX, y: frame.maxY + size.height)
        boss.zPosition = 6
        boss.name = "boss"
        
        let body = SKPhysicsBody(rectangleOf: size)
        body.isDynamic = true
        body.affectedByGravity = false
        body.allowsRotation = false
        body.categoryBitMask = PhysicsCategory.enemy
        body.collisionBitMask = 0
        body.contactTestBitMask = PhysicsCategory.arrow | PhysicsCategory.player
        boss.physicsBody = body
        
        let hpBase = 60 + level * 10
        if boss.userData == nil { boss.userData = NSMutableDictionary() }
        boss.userData?["hp"] = hpBase
        
        addChild(boss)
        currentBossNode = boss
        
        let distance = (boss.position.y - (frame.midY + 140))
        let duration = TimeInterval(distance / 90)
        let moveDown = SKAction.moveTo(y: frame.midY + 140, duration: duration)
        boss.run(moveDown)
    }
    
    // MARK: - Touch handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isPerkChoiceActive {
            handlePerkTouch(touches)
        } else if isGameOver {
            handleDeathTouch(touches)
        } else {
            movePlayer(touches)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isPerkChoiceActive || isGameOver { return }
        movePlayer(touches)
    }
    
    private func movePlayer(_ touches: Set<UITouch>) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let clampedX = min(max(location.x, frame.minX + playerNode.size.width / 2.0), frame.maxX - playerNode.size.width / 2.0)
        let newPosition = CGPoint(x: clampedX, y: playerNode.position.y)
        playerNode.run(SKAction.moveTo(x: newPosition.x, duration: 0.08))
    }
    
    // MARK: - Contacts
    func didBegin(_ contact: SKPhysicsContact) {
        let (first, second) = orderedBodies(contact)
        if first.categoryBitMask == PhysicsCategory.arrow && second.categoryBitMask == PhysicsCategory.enemy {
            guard let arrow = first.node as? SKSpriteNode, let enemy = second.node as? SKSpriteNode else { return }
            
            let isCrit = CGFloat.random(in: 0...1) < critChance
            let raw = CGFloat(baseArrowDamage) * (isCrit ? critMultiplier : 1.0)
            let damage = max(1, Int(ceil(raw)))
            
            let currentHP = (enemy.userData?["hp"] as? Int) ?? 1
            let newHP = currentHP - damage
            enemy.userData?["hp"] = newHP
            
            showDamagePopup(amount: damage, at: contact.contactPoint, isCrit: isCrit)
            triggerHapticHit(isCrit: isCrit)
            
            let flash = SKAction.sequence([
                .group([
                    .scale(to: 1.08, duration: 0.05),
                    .colorize(with: .white, colorBlendFactor: 0.7, duration: 0.05)
                ]),
                .group([
                    .scale(to: 1.0, duration: 0.08),
                    .colorize(withColorBlendFactor: 0.0, duration: 0.08)
                ])
            ])
            enemy.run(flash)
            
            if newHP <= 0 {
                if enemy.name == "boss" { dropCoins(at: enemy.position, bonus: 12); bossDefeated() } else { dropCoins(at: enemy.position) }
                enemy.removeFromParent()
                onEnemyKilled()
            }
            
            arrow.removeFromParent()
        } else if first.categoryBitMask == PhysicsCategory.player && second.categoryBitMask == PhysicsCategory.enemy {
            handlePlayerDeath()
        }
    }
    
    private func orderedBodies(_ contact: SKPhysicsContact) -> (SKPhysicsBody, SKPhysicsBody) {
        if contact.bodyA.categoryBitMask < contact.bodyB.categoryBitMask {
            return (contact.bodyA, contact.bodyB)
        } else {
            return (contact.bodyB, contact.bodyA)
        }
    }
    
    private func onEnemyKilled() {
        killsCount += 1
        if killsCount % 10 == 0 { presentPerkChoice() }
        if killsCount % 50 == 0 { spawnBoss() }
    }
    
    private func bossDefeated() {
        isBossActive = false
        startEnemySpawns()
    }
    
    // MARK: - Loot and HUD effects
    private func dropCoins(at position: CGPoint, bonus: Int = 0) {
        let num = Int.random(in: 1...2) + bonus
        let groundY = (playerNode?.position.y ?? frame.minY) + 18
        for i in 0..<num {
            let coin = SKSpriteNode(color: .systemYellow, size: CGSize(width: 10, height: 10))
            coin.name = "coin"
            coin.position = position
            coin.zPosition = 50
            coin.alpha = 0.0
            addChild(coin)
            
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let distance: CGFloat = 22 + CGFloat(i % 6) * 4
            let target = CGPoint(x: position.x + cos(angle) * distance, y: position.y + sin(angle) * distance)
            let appear = SKAction.fadeIn(withDuration: 0.08)
            let moveOut = SKAction.move(to: target, duration: 0.12)
            moveOut.timingMode = .easeOut
            
            let fallDistance = max(0, target.y - groundY)
            let fallDuration = TimeInterval(fallDistance / max(60, coinFallSpeedPointsPerSecond))
            let fallToRow = SKAction.moveTo(y: groundY, duration: fallDuration)
            fallToRow.timingMode = .easeIn
            
            coin.run(SKAction.sequence([appear, moveOut, fallToRow]))
        }
    }
    
    private func tryMagnetCoins() {
        guard let playerNode else { return }
        enumerateChildNodes(withName: "coin") { node, _ in
            let dx = playerNode.position.x - node.position.x
            let dy = playerNode.position.y - node.position.y
            let distance = hypot(dx, dy)
            if distance <= self.coinMagnetRadius {
                let duration: TimeInterval = 0.2
                let path = SKAction.move(to: playerNode.position, duration: duration)
                path.timingMode = .easeIn
                node.run(.sequence([path, .removeFromParent()]))
                self.onCoinPicked(amount: 1)
            }
        }
    }
    
    private func onCoinPicked(amount: Int) {
        coins += amount
        persistCoinsIncrease(by: amount)
        coinsLabel.removeAllActions()
        let bump = SKAction.sequence([
            .scale(to: 1.15, duration: 0.08),
            .scale(to: 1.0, duration: 0.12)
        ])
        coinsLabel.run(bump)
    }
    
    private func showDamagePopup(amount: Int, at position: CGPoint, isCrit: Bool) {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "\(amount)"
        label.fontSize = isCrit ? 18 : 14
        label.fontColor = isCrit ? .systemYellow : .white
        label.position = position
        label.zPosition = 200
        addChild(label)
        
        let driftX = CGFloat.random(in: -8...8)
        let move = SKAction.moveBy(x: driftX, y: 24, duration: 0.6)
        let fade = SKAction.fadeOut(withDuration: 0.6)
        let scale = SKAction.scale(to: isCrit ? 1.3 : 1.1, duration: 0.1)
        scale.timingMode = .easeOut
        label.run(SKAction.sequence([scale, .group([move, fade]), .removeFromParent()]))
    }
    
    // MARK: - Perk choice overlay
    private func presentPerkChoice() {
        if isPerkChoiceActive || isGameOver { return }
        isPerkChoiceActive = true
        
        removeAction(forKey: "autoFire")
        removeAction(forKey: "spawnEnemies")
        
        let overlay = SKNode()
        overlay.name = "perkOverlay"
        overlay.zPosition = 500
        
        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.6), size: frame.size)
        dim.position = CGPoint(x: frame.midX, y: frame.midY)
        dim.zPosition = 0
        overlay.addChild(dim)
        
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "Выбери перк"
        title.fontSize = 20
        title.fontColor = .white
        title.position = CGPoint(x: frame.midX, y: frame.midY + 120)
        title.zPosition = 1
        overlay.addChild(title)
        
        let choices = generatePerkChoices(count: 3)
        let spacing: CGFloat = 150
        for (i, perk) in choices.enumerated() {
            let node = buildPerkOptionNode(perk: perk)
            let x = frame.midX + (CGFloat(i) - 1) * spacing
            node.position = CGPoint(x: x, y: frame.midY)
            node.zPosition = 2
            node.name = "perkOption-\(i)"
            if node.userData == nil { node.userData = NSMutableDictionary() }
            node.userData?["perk"] = perkIdentifier(perk)
            overlay.addChild(node)
        }
        
        addChild(overlay)
        perkOverlay = overlay
    }
    
    private func handlePerkTouch(_ touches: Set<UITouch>) {
        guard let touch = touches.first, let overlay = perkOverlay else { return }
        let location = touch.location(in: self)
        let nodesAtPoint = nodes(at: location)
        for node in nodesAtPoint {
            if node.name?.hasPrefix("perkOption-") == true {
                applyPerkNode(node)
                break
            } else if let parent = node.parent, parent.name?.hasPrefix("perkOption-") == true {
                applyPerkNode(parent)
                break
            }
        }
    }
    
    private func applyPerkNode(_ node: SKNode) {
        guard let perkId = node.userData?["perk"] as? String else { return }
        applyPerk(identifier: perkId)
        level += 1
        triggerHapticPerk()
        dismissPerkChoice()
        startAutoFire()
        startEnemySpawns()
    }
    
    private func dismissPerkChoice() {
        perkOverlay?.removeFromParent()
        perkOverlay = nil
        isPerkChoiceActive = false
    }
    
    private func generatePerkChoices(count: Int) -> [PerkType] {
        var pool = PerkType.allCases
        pool.shuffle()
        return Array(pool.prefix(count))
    }
    
    private func buildPerkOptionNode(perk: PerkType) -> SKNode {
        let size = CGSize(width: 120, height: 120)
        let card = SKShapeNode(rectOf: size, cornerRadius: 14)
        card.fillColor = SKColor(white: 0.15, alpha: 0.9)
        card.strokeColor = SKColor(white: 1.0, alpha: 0.2)
        card.lineWidth = 2
        
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = perkTitle(perk)
        title.fontColor = .white
        title.fontSize = 14
        title.position = CGPoint(x: 0, y: 24)
        title.zPosition = 1
        card.addChild(title)
        
        let desc = SKLabelNode(fontNamed: "Menlo")
        desc.text = perkDescription(perk)
        desc.fontColor = SKColor(white: 1.0, alpha: 0.8)
        desc.fontSize = 11
        desc.position = CGPoint(x: 0, y: -10)
        desc.zPosition = 1
        desc.numberOfLines = 2
        desc.preferredMaxLayoutWidth = 100
        desc.lineBreakMode = .byWordWrapping
        card.addChild(desc)
        
        return card
    }
    
    private func perkTitle(_ perk: PerkType) -> String {
        switch perk {
        case .fireRate: return "Скорострельность"
        case .extraArrow: return "+1 стрела"
        case .critChance: return "Крит шанс"
        case .critDamage: return "Крит урон"
        case .magnet: return "Магнит монет"
        case .damage: return "+1 урон"
        }
    }
    
    private func perkDescription(_ perk: PerkType) -> String {
        switch perk {
        case .fireRate: return "Стреляешь быстрее"
        case .extraArrow: return "Больше стрел в залпе"
        case .critChance: return "+5% шанс крита"
        case .critDamage: return "+0.5x множитель крита"
        case .magnet: return "+20 радиус подбора монет"
        case .damage: return "+1 базовый урон"
        }
    }
    
    private func perkIdentifier(_ perk: PerkType) -> String {
        switch perk {
        case .fireRate: return "fireRate"
        case .extraArrow: return "extraArrow"
        case .critChance: return "critChance"
        case .critDamage: return "critDamage"
        case .magnet: return "magnet"
        case .damage: return "damage"
        }
    }
    
    private func applyPerk(identifier: String) {
        switch identifier {
        case "fireRate":
            fireInterval = max(0.3, fireInterval - 0.15)
        case "extraArrow":
            arrowsPerShot = min(arrowsPerShot + 1, 6)
        case "critChance":
            critChance = min(0.6, critChance + 0.05)
        case "critDamage":
            critMultiplier = min(4.0, critMultiplier + 0.5)
        case "magnet":
            coinMagnetRadius = min(200, coinMagnetRadius + 20)
        case "damage":
            baseArrowDamage += 1
        default:
            break
        }
    }
    
    // MARK: - Death & Restart
    private func handlePlayerDeath() {
        if isGameOver { return }
        isGameOver = true
        triggerHapticDeath()
        
        removeAction(forKey: "autoFire")
        removeAction(forKey: "spawnEnemies")
        
        enumerateChildNodes(withName: "arrow") { node, _ in node.removeFromParent() }
        enumerateChildNodes(withName: "enemy") { node, _ in node.removeAllActions() }
        if let boss = currentBossNode { boss.removeAllActions() }
        
        presentDeathOverlay()
    }
    
    private func presentDeathOverlay() {
        let overlay = SKNode()
        overlay.name = "deathOverlay"
        overlay.zPosition = 600
        
        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.7), size: frame.size)
        dim.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.addChild(dim)
        
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "Ты умер"
        title.fontSize = 22
        title.fontColor = .white
        title.position = CGPoint(x: frame.midX, y: frame.midY + 80)
        overlay.addChild(title)
        
        let stats = SKLabelNode(fontNamed: "Menlo")
        stats.text = "Kills: \(killsCount)  Coins: \(coins)"
        stats.fontSize = 14
        stats.fontColor = .white
        stats.position = CGPoint(x: frame.midX, y: frame.midY + 46)
        overlay.addChild(stats)
        
        let button = SKShapeNode(rectOf: CGSize(width: 160, height: 48), cornerRadius: 12)
        button.fillColor = SKColor(white: 0.2, alpha: 1)
        button.strokeColor = SKColor(white: 1, alpha: 0.3)
        button.lineWidth = 2
        button.position = CGPoint(x: frame.midX, y: frame.midY - 10)
        button.name = "restartButton"
        
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "Заново"
        label.fontSize = 16
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: -6)
        label.name = "restartButton"
        button.addChild(label)
        
        overlay.addChild(button)
        addChild(overlay)
        deathOverlay = overlay
    }
    
    private func handleDeathTouch(_ touches: Set<UITouch>) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let hitNodes = nodes(at: location)
        for node in hitNodes {
            if node.name == "restartButton" || node.parent?.name == "restartButton" {
                restartRun()
                break
            }
        }
    }
    
    private func restartRun() {
        let newScene = GameScene(size: size)
        newScene.scaleMode = scaleMode
        view?.presentScene(newScene, transition: .fade(withDuration: 0.3))
    }
    
    // MARK: - Persistence
    private func persistCoinsIncrease(by amount: Int) {
        let key = "TotalCoins"
        let current = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(current + amount, forKey: key)
    }
    
    // MARK: - Haptics
    private func triggerHapticHit(isCrit: Bool) {
        let generator = UIImpactFeedbackGenerator(style: isCrit ? .medium : .light)
        generator.prepare()
        generator.impactOccurred()
    }
    
    private func triggerHapticDeath() {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.error)
    }
    
    private func triggerHapticPerk() {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.success)
    }
    
    // MARK: - Frame update
    override func update(_ currentTime: TimeInterval) {
        enumerateChildNodes(withName: "arrow") { node, _ in
            if node.position.y > self.frame.maxY + 80 || node.position.y < self.frame.minY - 80 || node.position.x < self.frame.minX - 80 || node.position.x > self.frame.maxX + 80 {
                node.removeFromParent()
            }
        }
        if !isPerkChoiceActive && !isGameOver {
            tryMagnetCoins()
        }
    }
}
