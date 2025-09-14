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
    static let enemyProjectile: UInt32 = 1 << 4
}

private struct Theme {
    static let background = SKColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
    static let panelFill = SKColor(white: 0.15, alpha: 1.0)
    static let panelStroke = SKColor(white: 1.0, alpha: 0.25)
    static let hudText = SKColor.white
    static let hudCoins = SKColor.systemYellow
    static let progressFill = SKColor.systemGreen
    static let progressFull = SKColor.systemYellow
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

private enum EnhancedPerk: String, CaseIterable {
    case freezeArrows
    case ricochet
    case fireDoT
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
    private var fireInterval: TimeInterval = 0.8
    private var arrowSpeedPointsPerSecond: CGFloat = 900
    private var enemySpawnInterval: TimeInterval = 1.0
    private var enemySpeedPointsPerSecond: CGFloat = 120
    private var arrowParallelSpacing: CGFloat = 18
    
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
    private var bossHPBarBG: SKShapeNode?
    private var bossHPBarFill: SKSpriteNode?
    private var bossMaxHP: Int = 0
    
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
    
    // Visuals
    private var backgroundNode: SKSpriteNode!
    private var circleParticleTexture: SKTexture?
    private var gameCamera: SKCameraNode?
    private var soundEnabled: Bool = true
    private var hapticsEnabled: Bool = true
    private var isSettingsActive: Bool = false
    private var settingsOverlay: SKNode?
    private var pauseButton: SKShapeNode!
    private var perkProgressBG: SKShapeNode!
    private var perkProgressFill: SKSpriteNode!
    private var topSafeInset: CGFloat = 0
    // Perk rhythm
    private var nextPerkAtKills: Int = 7
    private var perksTaken: Int = 0
    private var killsAtLastPerk: Int = 0
    private var bossesDefeatedCount: Int = 0
    private var runStartTime: TimeInterval = 0
    
    // MARK: - Scene lifecycle
    override func didMove(to view: SKView) {
        backgroundColor = Theme.background
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        
        physicsBody = SKPhysicsBody(edgeLoopFrom: frame)
        physicsBody?.categoryBitMask = PhysicsCategory.world
        physicsBody?.collisionBitMask = 0
        physicsBody?.contactTestBitMask = 0
        
        setupBackground()
        setupCamera()
        prepareParticleTexture()
        configureEnemyTypes()
        setupPlayer()
        setupHUD()
        // Load UX preferences
        soundEnabled = UserDefaults.standard.object(forKey: "SoundEnabled") as? Bool ?? true
        hapticsEnabled = UserDefaults.standard.object(forKey: "HapticsEnabled") as? Bool ?? true
        topSafeInset = view.safeAreaInsets.top
        setupPauseButton()
        setupPerkProgress()
        applyPersistentUpgrades()
        startAutoFire()
        startEnemySpawns()
        updateHUD()
        // Ensure safe area is applied after layout on first launch
        DispatchQueue.main.async { [weak self] in
            self?.updateSafeAreaAndRelayout()
        }
        runStartTime = CACurrentMediaTime()
    }

    // Apply upgrades from shop
    private func applyPersistentUpgrades() {
        let dmgLevel = UserDefaults.standard.integer(forKey: "UG_damage")
        let fireLevel = UserDefaults.standard.integer(forKey: "UG_fire")
        let magnetLevel = UserDefaults.standard.integer(forKey: "UG_magnet")
        baseArrowDamage += max(0, dmgLevel)
        fireInterval = max(0.25, fireInterval - 0.04 * Double(fireLevel))
        coinMagnetRadius = min(260, coinMagnetRadius + CGFloat(20 * magnetLevel))
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        updateSafeAreaAndRelayout()
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
        killsLabel.fontColor = Theme.hudText
        killsLabel.position = CGPoint(x: frame.minX + 16, y: frame.maxY - 16)
        killsLabel.zPosition = 100
        killsLabel.addShadow()
        addChild(killsLabel)
        
        levelLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        levelLabel.horizontalAlignmentMode = .right
        levelLabel.verticalAlignmentMode = .top
        levelLabel.fontSize = 16
        levelLabel.fontColor = Theme.hudText
        levelLabel.position = CGPoint(x: frame.maxX - 16, y: frame.maxY - 16)
        levelLabel.zPosition = 100
        levelLabel.addShadow()
        addChild(levelLabel)
        
        coinsLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        coinsLabel.horizontalAlignmentMode = .center
        coinsLabel.verticalAlignmentMode = .top
        coinsLabel.fontSize = 16
        coinsLabel.fontColor = Theme.hudCoins
        coinsLabel.position = CGPoint(x: frame.midX, y: frame.maxY - 16)
        coinsLabel.zPosition = 100
        coinsLabel.addShadow()
        addChild(coinsLabel)
    }
    
    private func updateHUD() {
        killsLabel?.text = "Kills: \(killsCount)"
        levelLabel?.text = "Lvl: \(level)"
        coinsLabel?.text = "\u{1F4B0} \(coins)"
        updatePerkProgress()
    }

    // MARK: - Pause button & Settings
    private func setupPauseButton() {
        let radius: CGFloat = 16
        let button = SKShapeNode(circleOfRadius: radius)
        button.fillColor = Theme.panelFill
        button.strokeColor = Theme.panelStroke
        button.lineWidth = 2
        button.zPosition = 150
        button.position = CGPoint(x: frame.minX + 26, y: frame.maxY - 44 - topSafeInset)
        button.name = "pauseButton"
        
        // pause icon (II)
        let bar1 = SKShapeNode(rectOf: CGSize(width: 3, height: 12), cornerRadius: 1)
        bar1.fillColor = .white
        bar1.strokeColor = .clear
        bar1.position = CGPoint(x: -4, y: 0)
        let bar2 = SKShapeNode(rectOf: CGSize(width: 3, height: 12), cornerRadius: 1)
        bar2.fillColor = .white
        bar2.strokeColor = .clear
        bar2.position = CGPoint(x: 4, y: 0)
        button.addChild(bar1)
        button.addChild(bar2)
        
        addChild(button)
        pauseButton = button
    }

    private func presentSettingsOverlay() {
        if isSettingsActive || isGameOver || isPerkChoiceActive { return }
        isSettingsActive = true
        pauseGameplay()
        
        let overlay = SKNode()
        overlay.name = "settingsOverlay"
        overlay.zPosition = 700
        
        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.6), size: frame.size)
        dim.position = CGPoint(x: frame.midX, y: frame.midY)
        dim.name = "settingsDim"
        overlay.addChild(dim)
        
        let panel = SKShapeNode(rectOf: CGSize(width: 260, height: 180), cornerRadius: 16)
        panel.fillColor = Theme.panelFill
        panel.strokeColor = Theme.panelStroke
        panel.lineWidth = 2
        panel.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.addChild(panel)
        
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "Пауза"
        title.fontSize = 18
        title.fontColor = Theme.hudText
        title.position = CGPoint(x: 0, y: 56)
        panel.addChild(title)
        
        let soundRow = buildToggleRow(title: "Звук", isOn: soundEnabled, name: "toggleSound")
        soundRow.position = CGPoint(x: 0, y: 18)
        panel.addChild(soundRow)
        
        let hapticsRow = buildToggleRow(title: "Вибрация", isOn: hapticsEnabled, name: "toggleHaptics")
        hapticsRow.position = CGPoint(x: 0, y: -20)
        panel.addChild(hapticsRow)
        
        let resumeBtn = SKShapeNode(rectOf: CGSize(width: 180, height: 42), cornerRadius: 10)
        resumeBtn.fillColor = SKColor(white: 0.25, alpha: 1.0)
        resumeBtn.strokeColor = Theme.panelStroke
        resumeBtn.lineWidth = 2
        resumeBtn.position = CGPoint(x: 0, y: -66)
        resumeBtn.name = "resumeButton"
        let resumeLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        resumeLabel.text = "Продолжить"
        resumeLabel.fontSize = 14
        resumeLabel.fontColor = Theme.hudText
        resumeLabel.position = CGPoint(x: 0, y: -6)
        resumeLabel.name = "resumeButton"
        resumeBtn.addChild(resumeLabel)
        panel.addChild(resumeBtn)
        
        addChild(overlay)
        settingsOverlay = overlay
    }

    private func dismissSettingsOverlay() {
        settingsOverlay?.removeFromParent()
        settingsOverlay = nil
        isSettingsActive = false
        resumeGameplay()
    }

    private func buildToggleRow(title: String, isOn: Bool, name: String) -> SKNode {
        let row = SKNode()
        row.name = name
        
        let label = SKLabelNode(fontNamed: "Menlo")
        label.text = title
        label.fontSize = 14
        label.fontColor = .white
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: -100, y: -6)
        row.addChild(label)
        
        let track = SKShapeNode(rectOf: CGSize(width: 52, height: 26), cornerRadius: 13)
        track.fillColor = SKColor(white: 0.2, alpha: 1.0)
        track.strokeColor = Theme.panelStroke
        track.lineWidth = 2
        track.position = CGPoint(x: 84, y: -8)
        track.name = name
        row.addChild(track)
        
        let knob = SKShapeNode(circleOfRadius: 10)
        knob.fillColor = isOn ? .systemGreen : SKColor(white: 0.5, alpha: 1.0)
        knob.strokeColor = .clear
        knob.position = CGPoint(x: isOn ? 12 : -12, y: 0)
        knob.name = name
        track.addChild(knob)
        
        return row
    }

    private func handleSettingsTouch(_ touches: Set<UITouch>) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let nodesAtPoint = nodes(at: location)
        for node in nodesAtPoint {
            if node.name == "resumeButton" {
                dismissSettingsOverlay()
                return
            }
            if node.name == "toggleSound" {
                soundEnabled.toggle()
                UserDefaults.standard.set(soundEnabled, forKey: "SoundEnabled")
                settingsOverlay?.removeFromParent()
                settingsOverlay = nil
                isSettingsActive = false
                presentSettingsOverlay()
                return
            }
            if node.name == "toggleHaptics" {
                hapticsEnabled.toggle()
                UserDefaults.standard.set(hapticsEnabled, forKey: "HapticsEnabled")
                settingsOverlay?.removeFromParent()
                settingsOverlay = nil
                isSettingsActive = false
                presentSettingsOverlay()
                return
            }
        }
    }

    // MARK: - Perk progress
    private func setupPerkProgress() {
        let width: CGFloat = 140
        let height: CGFloat = 8
        let bg = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 4)
        bg.fillColor = SKColor(white: 0.2, alpha: 0.9)
        bg.strokeColor = Theme.panelStroke
        bg.lineWidth = 2
        bg.position = CGPoint(x: frame.midX, y: frame.maxY - 40 - topSafeInset)
        bg.zPosition = 100
        addChild(bg)
        perkProgressBG = bg
        
        let fill = SKSpriteNode(color: Theme.progressFill, size: CGSize(width: width - 4, height: height - 4))
        fill.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        fill.position = CGPoint(x: bg.position.x - (width - 4)/2, y: bg.position.y)
        fill.zPosition = 101
        addChild(fill)
        perkProgressFill = fill
        updatePerkProgress()
    }

    private func updatePerkProgress() {
        guard let fill = perkProgressFill else { return }
        let total = max(1, nextPerkAtKills - killsAtLastPerk)
        let done = max(0, killsCount - killsAtLastPerk)
        let progress = CGFloat(done) / CGFloat(total)
        fill.xScale = max(0.0, min(1.0, progress))
        fill.color = progress >= 0.999 ? Theme.progressFull : Theme.progressFill
    }

    private func updateSafeAreaAndRelayout() {
        guard let v = view else { return }
        topSafeInset = v.safeAreaInsets.top
        // Reposition pause button and progress bar
        if let button = pauseButton {
            button.position = CGPoint(x: frame.minX + 26, y: frame.maxY - 44 - topSafeInset)
        }
        if let bg = perkProgressBG, let fill = perkProgressFill {
            let width = bg.frame.width
            bg.position = CGPoint(x: frame.midX, y: frame.maxY - 40 - topSafeInset)
            fill.position = CGPoint(x: bg.position.x - (width - 4)/2, y: bg.position.y)
        }
    }
    
    private func setupBackground() {
        let bg = SKSpriteNode(color: Theme.background, size: frame.size)
        bg.position = CGPoint(x: frame.midX, y: frame.midY)
        bg.zPosition = -100
        addChild(bg)
        backgroundNode = bg
        
        // Subtle idle pulse
        let c1 = SKColor(red: 0.06, green: 0.05, blue: 0.10, alpha: 1)
        let c2 = SKColor(red: 0.10, green: 0.06, blue: 0.14, alpha: 1)
        let pulse = SKAction.sequence([
            .colorize(with: c2, colorBlendFactor: 0.35, duration: 1.2),
            .colorize(with: c1, colorBlendFactor: 0.2, duration: 1.2)
        ])
        bg.run(.repeatForever(pulse))
    }
    
    
    
    private func pulseBackgroundStrong() {
        guard let bg = backgroundNode else { return }
        let flash = SKAction.sequence([
            .colorize(with: .systemPurple, colorBlendFactor: 0.65, duration: 0.07),
            .colorize(withColorBlendFactor: 0.0, duration: 0.25)
        ])
        bg.run(flash)
    }
    
    private func setupCamera() {
        let cam = SKCameraNode()
        cam.position = CGPoint(x: frame.midX, y: frame.midY)
        addChild(cam)
        camera = cam
        gameCamera = cam
    }
    
    private func shakeCamera(intensity: CGFloat, duration: TimeInterval) {
        guard let cam = gameCamera else { return }
        let amplitudeX = intensity
        let amplitudeY = intensity
        let numberOfShakes = Int(ceil(duration / 0.015))
        var actions: [SKAction] = []
        for _ in 0..<numberOfShakes {
            let dx = CGFloat.random(in: -amplitudeX...amplitudeX)
            let dy = CGFloat.random(in: -amplitudeY...amplitudeY)
            actions.append(.moveBy(x: dx, y: dy, duration: 0.015))
            actions.append(.moveBy(x: -dx, y: -dy, duration: 0.015))
        }
        cam.run(.sequence(actions))
    }
    
    private func prepareParticleTexture() {
        // Create a small circle texture for emitters
        let node = SKShapeNode(circleOfRadius: 2)
        node.fillColor = .white
        node.strokeColor = .clear
        node.lineWidth = 0
        if let tex = view?.texture(from: node) {
            circleParticleTexture = tex
        }
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
        
        playAnySFX(["shoot.caf","shoot.wav","shoot.mp3"])
        // small adaptive assist: if игрок долго без перка, ускоряем залпы
        if killsCount < nextPerkAtKills - 2 {
            fireInterval = max(0.6, fireInterval - 0.02)
        }
        
        // Compute symmetric horizontal offsets so all arrows go straight up in parallel
        let spacing = arrowParallelSpacing
        var offsets: [CGFloat] = []
        if total == 1 {
            offsets = [0]
        } else {
            // offsets: centered around 0; works for even/odd counts
            // offset(k) = (k - (n-1)/2) * spacing
            for k in 0..<total {
                let offset = (CGFloat(k) - CGFloat(total - 1) / 2.0) * spacing
                offsets.append(offset)
            }
        }
        
        let margin: CGFloat = 12
        for dx in offsets {
            var startX = playerNode.position.x + dx
            startX = min(max(startX, frame.minX + margin), frame.maxX - margin)
            let start = CGPoint(x: startX, y: playerNode.position.y)
            spawnArrow(from: start, angleOffset: 0)
        }
    }
    
    private func spawnArrow(from origin: CGPoint, angleOffset: CGFloat) {
        let arrowSize = CGSize(width: 6, height: 18)
        let arrowShape = SKShapeNode(rectOf: arrowSize, cornerRadius: 3)
        arrowShape.fillColor = .systemGreen
        arrowShape.strokeColor = .systemGreen
        arrowShape.glowWidth = 6
        arrowShape.position = CGPoint(x: origin.x, y: origin.y + 28)
        arrowShape.zPosition = 5
        arrowShape.name = "arrow"
        
        let body = SKPhysicsBody(rectangleOf: arrowSize)
        body.isDynamic = true
        body.affectedByGravity = false
        body.allowsRotation = false
        body.categoryBitMask = PhysicsCategory.arrow
        body.collisionBitMask = 0
        body.contactTestBitMask = PhysicsCategory.enemy
        arrowShape.physicsBody = body
        
        addChild(arrowShape)
        
        let directionAngle = (.pi / 2.0) + angleOffset
        let dx = cos(directionAngle) * arrowSpeedPointsPerSecond
        let dy = sin(directionAngle) * arrowSpeedPointsPerSecond
        arrowShape.zRotation = directionAngle
        arrowShape.physicsBody?.velocity = CGVector(dx: dx, dy: dy)
        
        addTrail(to: arrowShape)
        
        let lifetime: TimeInterval = 2.5
        arrowShape.run(SKAction.sequence([.wait(forDuration: lifetime), .removeFromParent()]))
    }

    // MARK: - Boss patterns
    private func startBossPatterns() {
        guard let boss = currentBossNode else { return }
        // radial and aimed volleys sequence
        let waitShort = SKAction.wait(forDuration: 1.2)
        let waitLong = SKAction.wait(forDuration: 2.2)
        let radial = SKAction.run { [weak self] in self?.bossRadialBurst(count: 16, speed: 160) }
        let aimed = SKAction.run { [weak self] in self?.bossAimedVolley(shots: 5, spread: 0.2, speed: 180) }
        let seq = SKAction.repeatForever(SKAction.sequence([radial, waitShort, aimed, waitLong]))
        boss.run(seq, withKey: "bossPatterns")
    }
    
    private func bossRadialBurst(count: Int, speed: CGFloat) {
        guard let boss = currentBossNode else { return }
        for i in 0..<count {
            let angle = (CGFloat(i) / CGFloat(count)) * (.pi * 2)
            spawnEnemyProjectile(from: boss.position, angle: angle, speed: speed)
        }
    }
    
    private func bossAimedVolley(shots: Int, spread: CGFloat, speed: CGFloat) {
        guard let boss = currentBossNode else { return }
        let baseAngle: CGFloat
        if let player = playerNode {
            let dx = player.position.x - boss.position.x
            let dy = player.position.y - boss.position.y
            baseAngle = atan2(dy, dx)
        } else {
            baseAngle = -.pi / 2
        }
        let total = max(1, shots)
        for k in 0..<total {
            let t = total == 1 ? 0.0 : (CGFloat(k) - CGFloat(total - 1)/2.0)
            let angle = baseAngle + t * spread
            spawnEnemyProjectile(from: boss.position, angle: angle, speed: speed)
        }
    }
    
    private func spawnEnemyProjectile(from origin: CGPoint, angle: CGFloat, speed: CGFloat) {
        let size = CGSize(width: 8, height: 8)
        let node = SKShapeNode(circleOfRadius: size.width/2)
        node.fillColor = .systemPink
        node.strokeColor = .clear
        node.position = origin
        node.zPosition = 6
        node.name = "enemyProjectile"
        
        let body = SKPhysicsBody(circleOfRadius: size.width/2)
        body.isDynamic = true
        body.affectedByGravity = false
        body.allowsRotation = false
        body.categoryBitMask = PhysicsCategory.enemyProjectile
        body.collisionBitMask = 0
        body.contactTestBitMask = PhysicsCategory.player
        node.physicsBody = body
        addChild(node)
        
        let vx = cos(angle) * speed
        let vy = sin(angle) * speed
        node.physicsBody?.velocity = CGVector(dx: vx, dy: vy)
        node.run(SKAction.sequence([.wait(forDuration: 4.0), .removeFromParent()]))
    }
    
    private func addTrail(to node: SKNode) {
        guard let tex = circleParticleTexture else { return }
        let emitter = SKEmitterNode()
        emitter.particleTexture = tex
        emitter.particleBirthRate = 180
        emitter.particleLifetime = 0.22
        emitter.particleLifetimeRange = 0.05
        emitter.particlePositionRange = CGVector(dx: 2, dy: 2)
        emitter.particleSpeed = 0
        emitter.particleAlpha = 0.9
        emitter.particleAlphaRange = 0.1
        emitter.particleAlphaSpeed = -2.8
        emitter.particleScale = 0.35
        emitter.particleScaleRange = 0.1
        emitter.particleScaleSpeed = -1.2
        emitter.particleColor = .systemGreen
        emitter.particleBlendMode = .add
        emitter.zPosition = (node.zPosition - 1)
        emitter.targetNode = self
        node.addChild(emitter)
    }
    
    // MARK: - Enemies
    private func startEnemySpawns() {
        removeAction(forKey: "spawnEnemies")
        // spawn pacing uses the same global difficulty idea
        let t = max(1.0, CACurrentMediaTime() - runStartTime)
        let timeFactor = pow(t / 60.0, 0.35)
        let killFactor = pow(Double(max(1, killsCount)) / 30.0, 0.45)
        let perkFactor = 1.0 + Double(perksTaken) * 0.12
        let bossFactor = 1.0 + Double(bossesDefeatedCount) * 0.25
        let globalScale = max(1.0, timeFactor * killFactor * perkFactor * bossFactor)
        let base = enemySpawnInterval - TimeInterval(level) * 0.02
        let adjusted = max(0.2, base / min(3.0, globalScale))
        let wait = SKAction.wait(forDuration: adjusted)
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
        
        // Difficulty scaling formula based on time, kills, perks, bosses
        let t = max(1.0, CACurrentMediaTime() - runStartTime) // seconds since start
        let timeFactor = pow(t / 60.0, 0.35) // grows slowly каждую минуту
        let killFactor = pow(Double(max(1, killsCount)) / 30.0, 0.45)
        let perkFactor = 1.0 + Double(perksTaken) * 0.12
        let bossFactor = 1.0 + Double(bossesDefeatedCount) * 0.25
        let globalScale = max(1.0, timeFactor * killFactor * perkFactor * bossFactor)
        
        let hpScale = Int(Double(type.baseHP) * globalScale)
        let initialHP = max(2, hpScale)
        if enemy.userData == nil { enemy.userData = NSMutableDictionary() }
        enemy.userData?["hp"] = initialHP
        
        addChild(enemy)
        
        let distance = (enemy.position.y - (frame.minY - size.height))
        // Speed also scales with globalScale but мягче
        let speed = type.speed + CGFloat(globalScale) * 20 + CGFloat(level) * 2
        let duration = TimeInterval(distance / speed)
        let move = SKAction.moveTo(y: frame.minY - size.height, duration: duration)
        enemy.run(SKAction.sequence([move, .removeFromParent()]))
    }
    
    private func spawnBoss() {
        if isPerkChoiceActive || isGameOver || isBossActive { return }
        isBossActive = true
        removeAction(forKey: "spawnEnemies")
        // Clear screen from regular enemies and coins
        enumerateChildNodes(withName: "enemy") { node, _ in node.removeFromParent() }
        enumerateChildNodes(withName: "coin") { node, _ in node.removeFromParent() }
        playAnySFX(["boss.caf","boss.wav","boss.mp3"])
        
        let size = CGSize(width: 70, height: 70)
        let boss = SKSpriteNode(color: .purple, size: size)
        boss.position = CGPoint(x: frame.midX, y: frame.midY + 180)
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
        bossMaxHP = hpBase
        
        addChild(boss)
        currentBossNode = boss
        setupBossHPBar(maxHP: hpBase)
        // Start boss firing patterns
        startBossPatterns()
    }
    
    // MARK: - Touch handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isPerkChoiceActive {
            handlePerkTouch(touches)
            return
        }
        if isGameOver {
            handleDeathTouch(touches)
            return
        }
        if isSettingsActive {
            handleSettingsTouch(touches)
            return
        }
        // Check pause button hit
        if let touch = touches.first {
            let point = touch.location(in: self)
            let hit = nodes(at: point).contains { $0.name == "pauseButton" }
            if hit {
                // button tap animation
                pauseButton.removeAllActions()
                pauseButton.run(SKAction.sequence([
                    .scale(to: 0.92, duration: 0.07),
                    .scale(to: 1.0, duration: 0.09)
                ]))
                presentSettingsOverlay()
                return
            }
        }
        movePlayer(touches)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isPerkChoiceActive || isGameOver || isSettingsActive { return }
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
            guard let arrowNode = first.node, let enemy = second.node as? SKSpriteNode else { return }
            
            let isCrit = CGFloat.random(in: 0...1) < critChance
            let raw = CGFloat(baseArrowDamage) * (isCrit ? critMultiplier : 1.0)
            let damage = max(1, Int(ceil(raw)))
            
            // base hit
            applyDamage(to: enemy, amount: damage, showAt: contact.contactPoint, isCrit: isCrit)
            
            // Enhanced effects
            if hasFreeze { applyFreeze(to: enemy) }
            if hasFire { applyBurn(to: enemy) }
            if hasRicochet, let arrow = first.node as? SKNode {
                // simple ricochet: spawn one extra arrow towards first found enemy
                if let nearest = self.children.first(where: { $0.name == "enemy" && $0 !== enemy }) as? SKSpriteNode {
                    let dx = nearest.position.x - arrow.position.x
                    let dy = nearest.position.y - arrow.position.y
                    let ang = atan2(dy, dx)
                    self.spawnArrow(from: arrow.position, angleOffset: ang - .pi/2)
                }
            }
            
            arrowNode.removeFromParent()
        } else if first.categoryBitMask == PhysicsCategory.player && second.categoryBitMask == PhysicsCategory.enemy {
            handlePlayerDeath()
        } else if first.categoryBitMask == PhysicsCategory.player && second.categoryBitMask == PhysicsCategory.enemyProjectile {
            // Player hit by boss projectile
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
        // Приоритет: босс важнее перка, чтобы перк-оверлей не блокировал спавн босса
        if killsCount % 50 == 0 {
            spawnBoss()
        } else if killsCount >= nextPerkAtKills {
            presentPerkChoice()
            // dynamic next thresholds: 7 -> 15 -> 25 -> 40 -> 60 ...
            perksTaken += 1
            nextPerkAtKills += [8, 10, 15, 20].min() ?? 10
        }
        pulseBackgroundStrong()
        // Recompute spawn pacing as difficulty ramps
        if !isBossActive && !isPerkChoiceActive { startEnemySpawns() }
    }
    
    private func bossDefeated() {
        isBossActive = false
        bossesDefeatedCount += 1
        startEnemySpawns()
        // Remove boss HP bar
        bossHPBarBG?.removeFromParent()
        bossHPBarFill?.removeFromParent()
        bossHPBarBG = nil
        bossHPBarFill = nil
        bossMaxHP = 0
        // Present enhanced perk choices
        presentEnhancedPerkChoice()
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
            
            // Idle bob + shimmer
            let bob = SKAction.sequence([
                .moveBy(x: 0, y: 2, duration: 0.35),
                .moveBy(x: 0, y: -2, duration: 0.35)
            ])
            bob.timingMode = .easeInEaseOut
            let flip = SKAction.sequence([
                .scaleX(to: 0.7, duration: 0.25),
                .scaleX(to: 1.0, duration: 0.25)
            ])
            flip.timingMode = .easeInEaseOut
            coin.run(.repeatForever(.group([bob, flip])))
            
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
            
            coin.run(.sequence([appear, moveOut, fallToRow]))
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
                self.playAnySFX(["coin.caf","coin.wav","coin.mp3"])
            }
        }
    }

    // MARK: - Boss HP bar
    private func setupBossHPBar(maxHP: Int) {
        let width: CGFloat = 220
        let height: CGFloat = 12
        let bg = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 6)
        bg.fillColor = SKColor(white: 0.2, alpha: 0.95)
        bg.strokeColor = Theme.panelStroke
        bg.lineWidth = 2
        bg.position = CGPoint(x: frame.midX, y: frame.maxY - 80 - topSafeInset)
        bg.zPosition = 300
        addChild(bg)
        bossHPBarBG = bg
        
        let fill = SKSpriteNode(color: .systemRed, size: CGSize(width: width - 6, height: height - 6))
        fill.anchorPoint = CGPoint(x: 0.0, y: 0.5)
        fill.position = CGPoint(x: bg.position.x - (width - 6)/2, y: bg.position.y)
        fill.zPosition = 301
        addChild(fill)
        bossHPBarFill = fill
        updateBossHPBar(currentHP: maxHP, maxHP: maxHP)
    }
    
    private func updateBossHPBar(currentHP: Int, maxHP: Int) {
        guard let fill = bossHPBarFill else { return }
        let progress = max(0.0, min(1.0, CGFloat(currentHP) / CGFloat(maxHP)))
        fill.xScale = progress
        fill.color = progress > 0.5 ? .systemGreen : (progress > 0.25 ? .systemOrange : .systemRed)
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
    
    // MARK: - Damage application helpers
    private func applyDamage(to enemy: SKSpriteNode, amount: Int, showAt: CGPoint, isCrit: Bool) {
        let currentHP = (enemy.userData?["hp"] as? Int) ?? 1
        let newHP = currentHP - amount
        enemy.userData?["hp"] = newHP
        if enemy.name == "boss" {
            updateBossHPBar(currentHP: max(0, newHP), maxHP: max(1, bossMaxHP))
        }
        showDamagePopup(amount: amount, at: showAt, isCrit: isCrit)
        triggerHapticHit(isCrit: isCrit)
        playAnySFX(["hit.caf","hit.wav","hit.mp3"])
        shakeCamera(intensity: isCrit ? 6 : 3, duration: 0.08)
        
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
            if enemy.name == "boss" { dropCoins(at: enemy.position, bonus: 12); bossDefeated(); spawnDeathBurst(at: enemy.position, isBoss: true); shakeCamera(intensity: 12, duration: 0.25); playAnySFX(["boss.caf","boss.wav","boss.mp3"]) } else { dropCoins(at: enemy.position); spawnDeathBurst(at: enemy.position, isBoss: false); playAnySFX(["death.caf","death.wav","death.mp3"]) }
            enemy.removeFromParent()
            onEnemyKilled()
        }
    }
    
    private func applyFreeze(to enemy: SKSpriteNode) {
        let slow = SKAction.speed(to: 0.6, duration: 0.0)
        let restore = SKAction.speed(to: 1.0, duration: 0.0)
        enemy.run(SKAction.sequence([slow, .wait(forDuration: 0.6), restore]))
        enemy.color = .systemTeal
        enemy.colorBlendFactor = 0.6
        enemy.run(.sequence([.wait(forDuration: 0.6), .colorize(withColorBlendFactor: 0.0, duration: 0.1)]))
    }
    
    private func applyBurn(to enemy: SKSpriteNode) {
        let ticks = 3
        let interval: TimeInterval = 0.4
        for i in 1...ticks {
            run(.sequence([
                .wait(forDuration: interval * Double(i)),
                .run { [weak self, weak enemy] in
                    guard let self, let enemy = enemy, enemy.parent != nil else { return }
                    self.applyDamage(to: enemy, amount: max(1, self.baseArrowDamage / 2), showAt: enemy.position, isCrit: false)
                }
            ]))
        }
        enemy.run(.sequence([
            .colorize(with: .systemOrange, colorBlendFactor: 0.6, duration: 0.05),
            .wait(forDuration: interval * Double(ticks)),
            .colorize(withColorBlendFactor: 0.0, duration: 0.1)
        ]))
    }
    
    // MARK: - Perk choice overlay
    private func presentPerkChoice() {
        if isPerkChoiceActive || isGameOver { return }
        isPerkChoiceActive = true
        
        removeAction(forKey: "autoFire")
        removeAction(forKey: "spawnEnemies")
        pauseGameplay()
        
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

    private func presentEnhancedPerkChoice() {
        if isPerkChoiceActive || isGameOver { return }
        isPerkChoiceActive = true
        pauseGameplay()
        
        let overlay = SKNode()
        overlay.name = "perkOverlay"
        overlay.zPosition = 500
        
        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.6), size: frame.size)
        dim.position = CGPoint(x: frame.midX, y: frame.midY)
        dim.zPosition = 0
        overlay.addChild(dim)
        
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "Награда босса"
        title.fontSize = 20
        title.fontColor = .white
        title.position = CGPoint(x: frame.midX, y: frame.midY + 120)
        title.zPosition = 1
        overlay.addChild(title)
        
        let perks = generateEnhancedPerks(count: 3)
        let spacing: CGFloat = 150
        for (i, p) in perks.enumerated() {
            let node = buildEnhancedPerkOptionNode(perk: p)
            let x = frame.midX + (CGFloat(i) - 1) * spacing
            node.position = CGPoint(x: x, y: frame.midY)
            node.zPosition = 2
            node.name = "enhPerk-\(i)"
            if node.userData == nil { node.userData = NSMutableDictionary() }
            node.userData?["enh"] = p
            overlay.addChild(node)
        }
        addChild(overlay)
        perkOverlay = overlay
    }
    
    private func handlePerkTouch(_ touches: Set<UITouch>) {
        guard let touch = touches.first, perkOverlay != nil else { return }
        let location = touch.location(in: self)
        let nodesAtPoint = nodes(at: location)
        for node in nodesAtPoint {
            if node.name?.hasPrefix("perkOption-") == true {
                applyPerkNode(node)
                break
            } else if let parent = node.parent, parent.name?.hasPrefix("perkOption-") == true {
                applyPerkNode(parent)
                break
            } else if node.name?.hasPrefix("enhPerk-") == true {
                applyEnhancedPerkNode(node)
                break
            } else if let parent = node.parent, parent.name?.hasPrefix("enhPerk-") == true {
                applyEnhancedPerkNode(parent)
                break
            }
        }
    }
    
    private func applyPerkNode(_ node: SKNode) {
        guard let perkId = node.userData?["perk"] as? String else { return }
        applyPerk(identifier: perkId)
        level += 1
        triggerHapticPerk()
        playAnySFX(["perk.caf","perk.wav","perk.mp3"])
        dismissPerkChoice()
        resumeGameplay()
        startAutoFire()
        startEnemySpawns()
        // ramp next perk threshold and refresh progress bar
        killsAtLastPerk = killsCount
        nextPerkAtKills = killsCount + (perksTaken == 0 ? 8 : perksTaken == 1 ? 10 : perksTaken == 2 ? 15 : 20)
        updatePerkProgress()
    }
    
    private func dismissPerkChoice() {
        perkOverlay?.removeFromParent()
        perkOverlay = nil
        isPerkChoiceActive = false
    }
    
    private func pauseGameplay() {
        physicsWorld.speed = 0
        enumerateChildNodes(withName: "enemy") { node, _ in node.isPaused = true }
        enumerateChildNodes(withName: "arrow") { node, _ in node.isPaused = true }
        enumerateChildNodes(withName: "coin") { node, _ in node.isPaused = true }
        currentBossNode?.isPaused = true
        // stop auto actions
        removeAction(forKey: "autoFire")
        removeAction(forKey: "spawnEnemies")
    }
    
    private func resumeGameplay() {
        physicsWorld.speed = 1
        enumerateChildNodes(withName: "enemy") { node, _ in node.isPaused = false }
        enumerateChildNodes(withName: "arrow") { node, _ in node.isPaused = false }
        enumerateChildNodes(withName: "coin") { node, _ in node.isPaused = false }
        currentBossNode?.isPaused = false
        // resume auto actions
        startAutoFire()
        if !isBossActive { startEnemySpawns() }
    }

    private func generatePerkChoices(count: Int) -> [PerkType] {
        var pool = PerkType.allCases
        pool.shuffle()
        return Array(pool.prefix(count))
    }
    
    private func generateEnhancedPerks(count: Int) -> [EnhancedPerk] {
        var pool = EnhancedPerk.allCases
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
    
    private func buildEnhancedPerkOptionNode(perk: EnhancedPerk) -> SKNode {
        let size = CGSize(width: 130, height: 130)
        let card = SKShapeNode(rectOf: size, cornerRadius: 16)
        card.fillColor = SKColor(white: 0.16, alpha: 1.0)
        card.strokeColor = .systemYellow
        card.lineWidth = 2
        
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = enhancedPerkTitle(perk)
        title.fontColor = .white
        title.fontSize = 14
        title.position = CGPoint(x: 0, y: 24)
        title.zPosition = 1
        card.addChild(title)
        
        let desc = SKLabelNode(fontNamed: "Menlo")
        desc.text = enhancedPerkDescription(perk)
        desc.fontColor = SKColor(white: 1.0, alpha: 0.85)
        desc.fontSize = 11
        desc.position = CGPoint(x: 0, y: -10)
        desc.zPosition = 1
        desc.numberOfLines = 2
        desc.preferredMaxLayoutWidth = 110
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
    
    private func enhancedPerkTitle(_ p: EnhancedPerk) -> String {
        switch p {
        case .freezeArrows: return "Заморозка"
        case .ricochet: return "Рикошет"
        case .fireDoT: return "Горение"
        }
    }
    
    private func enhancedPerkDescription(_ p: EnhancedPerk) -> String {
        switch p {
        case .freezeArrows: return "Стрелы замедляют врагов"
        case .ricochet: return "Стрелы отскакивают от врагов"
        case .fireDoT: return "Стрелы поджигают на время"
        }
    }
    
    private func applyEnhancedPerkNode(_ node: SKNode) {
        guard let raw = node.userData?["enh"] as? String ?? (node.userData?["enh"] as? EnhancedPerk)?.rawValue else { return }
        let p = EnhancedPerk(rawValue: raw) ?? .ricochet
        applyEnhancedPerk(p)
        triggerHapticPerk()
        playAnySFX(["perk.caf","perk.wav","perk.mp3"])
        dismissPerkChoice()
        resumeGameplay()
        startAutoFire()
        startEnemySpawns()
    }
    
    // Flags for enhanced effects
    private var hasFreeze: Bool = false
    private var hasRicochet: Bool = false
    private var hasFire: Bool = false
    
    private func applyEnhancedPerk(_ p: EnhancedPerk) {
        switch p {
        case .freezeArrows: hasFreeze = true
        case .ricochet: hasRicochet = true
        case .fireDoT: hasFire = true
        }
    }
    
    // MARK: - Death & Restart
    private func handlePlayerDeath() {
        if isGameOver { return }
        isGameOver = true
        triggerHapticDeath()
        playAnySFX(["death.caf","death.wav","death.mp3"])
        // save best score
        let bestKey = "BestKills"
        let best = UserDefaults.standard.integer(forKey: bestKey)
        if killsCount > best { UserDefaults.standard.set(killsCount, forKey: bestKey) }
        
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

        let menuBtn = SKShapeNode(rectOf: CGSize(width: 160, height: 44), cornerRadius: 12)
        menuBtn.fillColor = SKColor(white: 0.2, alpha: 1)
        menuBtn.strokeColor = SKColor(white: 1, alpha: 0.3)
        menuBtn.lineWidth = 2
        menuBtn.position = CGPoint(x: frame.midX, y: frame.midY - 64)
        menuBtn.name = "menuButton"
        let mLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        mLabel.text = "В меню"
        mLabel.fontSize = 16
        mLabel.fontColor = .white
        mLabel.position = CGPoint(x: 0, y: -6)
        mLabel.name = "menuButton"
        menuBtn.addChild(mLabel)
        overlay.addChild(menuBtn)
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
            } else if node.name == "menuButton" || node.parent?.name == "menuButton" {
                goToMenu()
                break
            }
        }
    }
    
    private func restartRun() {
        let newScene = GameScene(size: size)
        newScene.scaleMode = scaleMode
        view?.presentScene(newScene, transition: .fade(withDuration: 0.3))
    }

    private func goToMenu() {
        let scene = MenuScene(size: size)
        scene.scaleMode = scaleMode
        view?.presentScene(scene, transition: .fade(withDuration: 0.3))
    }
    
    // MARK: - Persistence
    private func persistCoinsIncrease(by amount: Int) {
        let key = "TotalCoins"
        let current = UserDefaults.standard.integer(forKey: key)
        let updated = current + amount
        UserDefaults.standard.set(updated, forKey: key)
    }
    
    // MARK: - Haptics
    private func triggerHapticHit(isCrit: Bool) {
        guard hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: isCrit ? .medium : .light)
        generator.prepare()
        generator.impactOccurred()
    }
    
    private func triggerHapticDeath() {
        guard hapticsEnabled else { return }
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.error)
    }
    
    private func triggerHapticPerk() {
        guard hapticsEnabled else { return }
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
    
    private func spawnDeathBurst(at position: CGPoint, isBoss: Bool) {
        guard let tex = circleParticleTexture else { return }
        let emitter = SKEmitterNode()
        emitter.particleTexture = tex
        emitter.particleBirthRate = 0
        emitter.numParticlesToEmit = isBoss ? 220 : 70
        emitter.particleLifetime = isBoss ? 0.6 : 0.4
        emitter.particlePosition = position
        emitter.particlePositionRange = CGVector(dx: isBoss ? 80 : 40, dy: isBoss ? 80 : 40)
        emitter.particleSpeed = isBoss ? 220 : 160
        emitter.particleSpeedRange = 80
        emitter.emissionAngleRange = .pi * 2
        emitter.particleAlpha = 0.9
        emitter.particleAlphaSpeed = -2.0
        emitter.particleScale = isBoss ? 0.7 : 0.5
        emitter.particleScaleRange = 0.2
        emitter.particleScaleSpeed = -1.5
        emitter.particleBlendMode = .add
        emitter.particleColor = isBoss ? .systemPurple : .systemPink
        emitter.zPosition = 60
        addChild(emitter)
        
        // Emit by triggering birth rate briefly
        emitter.particleBirthRate = isBoss ? 800 : 600
        emitter.run(.sequence([.wait(forDuration: 0.08), .run { emitter.particleBirthRate = 0 }, .wait(forDuration: 0.7), .removeFromParent()]))
    }
    
    // MARK: - SFX
    private func playAnySFX(_ names: [String]) {
        guard soundEnabled else { return }
        for name in names {
            if Bundle.main.url(forResource: name, withExtension: nil) != nil {
                run(SKAction.playSoundFileNamed(name, waitForCompletion: false))
                break
            }
        }
    }
}

// MARK: - Small utilities
private extension SKLabelNode {
    func addShadow() {
        let shadow = SKLabelNode(fontNamed: self.fontName)
        shadow.text = self.text ?? ""
        shadow.fontSize = self.fontSize
        shadow.fontColor = SKColor(white: 0, alpha: 0.6)
        shadow.position = CGPoint(x: 1.0, y: -1.0)
        shadow.zPosition = (self.zPosition - 1)
        shadow.alpha = 0.6
        shadow.name = "shadow"
        self.addChild(shadow)
    }
}
