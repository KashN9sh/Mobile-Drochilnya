import SpriteKit
import UIKit

class MenuScene: SKScene {
    private var coinsLabel: SKLabelNode!
    private var bestLabel: SKLabelNode!
    
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
        setupUI()
        updateLabels()
    }
    
    private func setupUI() {
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "Dopamine Archer"
        title.fontSize = 24
        title.fontColor = .white
        title.position = CGPoint(x: frame.midX, y: frame.midY + 140)
        addChild(title)
        
        bestLabel = SKLabelNode(fontNamed: "Menlo")
        bestLabel.fontSize = 14
        bestLabel.fontColor = .white
        bestLabel.position = CGPoint(x: frame.midX, y: frame.midY + 100)
        addChild(bestLabel)
        
        coinsLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        coinsLabel.fontSize = 16
        coinsLabel.fontColor = .systemYellow
        coinsLabel.position = CGPoint(x: frame.midX, y: frame.midY + 70)
        addChild(coinsLabel)
        
        addChild(makeButton(text: "Играть", name: "playButton", y: frame.midY + 16))
        addChild(makeButton(text: "Магазин", name: "shopButton", y: frame.midY - 40))
    }
    
    private func makeButton(text: String, name: String, y: CGFloat) -> SKNode {
        let node = SKShapeNode(rectOf: CGSize(width: 220, height: 48), cornerRadius: 12)
        node.fillColor = SKColor(white: 0.2, alpha: 1)
        node.strokeColor = SKColor(white: 1, alpha: 0.25)
        node.lineWidth = 2
        node.position = CGPoint(x: frame.midX, y: y)
        node.name = name
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = 16
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: -6)
        label.name = name
        node.addChild(label)
        return node
    }
    
    private func updateLabels() {
        let best = UserDefaults.standard.integer(forKey: "BestKills")
        let coins = UserDefaults.standard.integer(forKey: "TotalCoins")
        bestLabel.text = "Рекорд: \(best)"
        coinsLabel.text = "\u{1F4B0} \(coins)"
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let nodesAtPoint = nodes(at: point)
        for n in nodesAtPoint {
            if n.name == "playButton" { startGame(); return }
            if n.name == "shopButton" { presentShop(); return }
        }
    }
    
    private func startGame() {
        let scene = GameScene(size: size)
        scene.scaleMode = scaleMode
        view?.presentScene(scene, transition: .fade(withDuration: 0.3))
    }
    
    private func presentShop() {
        let scene = ShopScene(size: size)
        scene.scaleMode = scaleMode
        view?.presentScene(scene, transition: .moveIn(with: .right, duration: 0.3))
    }
}


