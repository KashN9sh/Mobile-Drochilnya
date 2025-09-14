import SpriteKit
import UIKit

class ShopScene: SKScene {
    private var coinsLabel: SKLabelNode!
    
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
        setupUI()
        updateCoins()
    }
    
    private func setupUI() {
        addChild(makeButton(text: "Назад", name: "backButton", y: frame.maxY - 60))
        coinsLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        coinsLabel.fontSize = 16
        coinsLabel.fontColor = .systemYellow
        coinsLabel.position = CGPoint(x: frame.midX, y: frame.maxY - 100)
        addChild(coinsLabel)
        
        // Three basic upgrades: damage, fire rate, magnet
        addChild(makeUpgrade(title: "+1 Урон", key: "UG_damage", priceKey: "UG_damage_price", basePrice: 50, y: frame.midY + 60))
        addChild(makeUpgrade(title: "Скорострельность", key: "UG_fire", priceKey: "UG_fire_price", basePrice: 80, y: frame.midY))
        addChild(makeUpgrade(title: "Магнит +20", key: "UG_magnet", priceKey: "UG_magnet_price", basePrice: 60, y: frame.midY - 60))
    }
    
    private func makeButton(text: String, name: String, y: CGFloat) -> SKNode {
        let node = SKShapeNode(rectOf: CGSize(width: 120, height: 40), cornerRadius: 10)
        node.fillColor = SKColor(white: 0.2, alpha: 1)
        node.strokeColor = SKColor(white: 1, alpha: 0.25)
        node.lineWidth = 2
        node.position = CGPoint(x: frame.minX + 80, y: y)
        node.name = name
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = 14
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: -6)
        label.name = name
        node.addChild(label)
        return node
    }
    
    private func makeUpgrade(title: String, key: String, priceKey: String, basePrice: Int, y: CGFloat) -> SKNode {
        let container = SKNode()
        container.position = CGPoint(x: frame.midX, y: y)
        
        let panel = SKShapeNode(rectOf: CGSize(width: 260, height: 50), cornerRadius: 12)
        panel.fillColor = SKColor(white: 0.2, alpha: 1)
        panel.strokeColor = SKColor(white: 1, alpha: 0.25)
        panel.lineWidth = 2
        panel.name = "buy_\(key)"
        container.addChild(panel)
        
        let label = SKLabelNode(fontNamed: "Menlo")
        label.text = title
        label.fontSize = 14
        label.fontColor = .white
        label.position = CGPoint(x: -70, y: -6)
        label.horizontalAlignmentMode = .left
        container.addChild(label)
        
        let level = UserDefaults.standard.integer(forKey: key)
        let price = UserDefaults.standard.integer(forKey: priceKey)
        let cost = price > 0 ? price : basePrice * max(1, level + 1)
        let costLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        costLabel.text = "\u{1F4B0} \(cost)"
        costLabel.fontSize = 14
        costLabel.fontColor = .systemYellow
        costLabel.position = CGPoint(x: 80, y: -6)
        costLabel.name = "cost_\(key)"
        container.addChild(costLabel)
        
        panel.userData = NSMutableDictionary()
        panel.userData?["key"] = key
        panel.userData?["priceKey"] = priceKey
        panel.userData?["basePrice"] = basePrice
        return container
    }
    
    private func updateCoins() {
        let coins = UserDefaults.standard.integer(forKey: "TotalCoins")
        coinsLabel.text = "\u{1F4B0} \(coins)"
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let nodesAtPoint = nodes(at: point)
        for n in nodesAtPoint {
            if n.name == "backButton" { goBack(); return }
            if let panel = (n as? SKShapeNode) ?? (n.parent as? SKShapeNode), let name = panel.name, name.hasPrefix("buy_") {
                handleBuy(panel)
                return
            }
        }
    }
    
    private func goBack() {
        let scene = MenuScene(size: size)
        scene.scaleMode = scaleMode
        view?.presentScene(scene, transition: .moveIn(with: .left, duration: 0.3))
    }
    
    private func handleBuy(_ panel: SKShapeNode) {
        guard let key = panel.userData?["key"] as? String,
              let priceKey = panel.userData?["priceKey"] as? String,
              let basePrice = panel.userData?["basePrice"] as? Int else { return }
        var coins = UserDefaults.standard.integer(forKey: "TotalCoins")
        let level = UserDefaults.standard.integer(forKey: key)
        let currentCost = max(basePrice * max(1, level + 1), UserDefaults.standard.integer(forKey: priceKey))
        if coins < currentCost { return }
        coins -= currentCost
        UserDefaults.standard.set(coins, forKey: "TotalCoins")
        UserDefaults.standard.set(level + 1, forKey: key)
        UserDefaults.standard.set(currentCost + basePrice, forKey: priceKey)
        updateCoins()
        // Update cost label
        if let costLabel = childNode(withName: "cost_\(key)") as? SKLabelNode {
            costLabel.text = "\u{1F4B0} \(currentCost + basePrice)"
        }
    }
}


