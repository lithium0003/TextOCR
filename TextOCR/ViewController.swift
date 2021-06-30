//
//  ViewController.swift
//  TextOCR
//
//  Created by rei8 on 2021/05/18.
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var resultText: UITextView!
    @IBOutlet weak var drawView: DrawView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.

        drawView.layer.borderColor = UIColor.systemGreen.cgColor
        drawView.layer.borderWidth = 2.0

        let myView = UIView(frame: CGRect(x: 0, y: 0, width: 768, height: 640))
        myView.backgroundColor = .clear
        myView.layer.position = CGPoint(x: 384, y: 320)
        myView.alpha = 0.2
        let shapeLayer = CAShapeLayer()
        shapeLayer.frame = CGRect(x: 0, y: 0, width: 768, height: 640)
        shapeLayer.fillColor = UIColor.gray.cgColor
        myView.layer.addSublayer(shapeLayer)
        let path = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 768, height: 640))
        for x in 0..<6 {
            for y in 0..<5 {
                path.append(UIBezierPath(rect: CGRect(x: 16 + x * 128, y: 16 + y * 128, width: 96, height: 96)))
            }
        }
        shapeLayer.path = path.cgPath
        shapeLayer.fillRule = .evenOdd
        
        drawView.addSubview(myView)

        let myView2 = UIView(frame: CGRect(x: 0, y: 0, width: 768, height: 640))
        myView2.backgroundColor = .clear
        myView2.layer.position = CGPoint(x: 384, y: 320)
        myView2.alpha = 0.5
        let shapeLayer2 = CAShapeLayer()
        shapeLayer2.frame = CGRect(x: 0, y: 0, width: 768, height: 640)
        shapeLayer2.strokeColor = UIColor.systemGreen.cgColor
        myView2.layer.addSublayer(shapeLayer2)
        let path2 = UIBezierPath()
        for x in 0...6 {
            path2.move(to: CGPoint(x: x * 128, y: 0))
            path2.addLine(to: CGPoint(x: x * 128, y: 640))
        }
        for y in 0...5 {
            path2.move(to: CGPoint(x: 0, y: y * 128))
            path2.addLine(to: CGPoint(x: 768, y: y * 128))
        }
        shapeLayer2.path = path2.cgPath

        drawView.addSubview(myView2)
        animateDirection()
    }

    @IBAction func runTaped(_ sender: Any) {
        guard let image = drawView.snapshotImage else {
            return
        }
        resultText.text = "Running..."
        Detector.callDetect(for: image) { str in
            DispatchQueue.main.async {
                self.resultText.text = str
            }
        }
    }
    
    @IBAction func clearTaped(_ sender: Any) {
        drawView.clear()
    }
    
    @IBAction func usePencilChanged(_ sender: UISwitch) {
        drawView.useFinger = !sender.isOn
    }
    
    func animateDirection() {
        CATransaction.begin()
        let myView = UIView(frame: CGRect(x: 0, y: 0, width: 768, height: 640))
        myView.backgroundColor = .clear
        myView.layer.position = CGPoint(x: 384, y: 320)
        CATransaction.setCompletionBlock({
            myView.removeFromSuperview()
        })
        let shapeLayer = CAShapeLayer()
        shapeLayer.frame = CGRect(x: 0, y: 0, width: 768, height: 640)
        shapeLayer.strokeColor = UIColor.black.cgColor
        shapeLayer.lineWidth = 3
        let shapeLayer2 = CAShapeLayer()
        shapeLayer2.frame = CGRect(x: 0, y: 0, width: 768, height: 640)
        shapeLayer2.strokeColor = UIColor.black.cgColor
        shapeLayer2.lineWidth = 3
        let path = UIBezierPath()
        if Detector.isVertical {
            path.move(to: CGPoint(x: 5 * 128 + 64, y: 64))
            path.addLine(to: CGPoint(x: 5 * 128 + 64, y: 4 * 128 + 64))
        }
        else {
            path.move(to: CGPoint(x: 64, y: 64))
            path.addLine(to: CGPoint(x: 5 * 128 + 64, y: 64))
        }
        shapeLayer.path = path.cgPath
        let path2 = UIBezierPath()
        if Detector.isVertical {
            path2.move(to: CGPoint(x: 5 * 128 + 64, y: 64))
            path2.addLine(to: CGPoint(x: 5 * 128 + 64 + 16, y: 64 - 16))
            path2.move(to: CGPoint(x: 5 * 128 + 64, y: 64))
            path2.addLine(to: CGPoint(x: 5 * 128 + 64 - 16, y: 64 - 16))
        }
        else {
            path2.move(to: CGPoint(x: 64, y: 64))
            path2.addLine(to: CGPoint(x: 64 - 16, y: 64 + 16))
            path2.move(to: CGPoint(x: 64, y: 64))
            path2.addLine(to: CGPoint(x: 64 - 16, y: 64 - 16))
        }
        shapeLayer2.path = path2.cgPath

        myView.layer.addSublayer(shapeLayer)
        myView.layer.addSublayer(shapeLayer2)
        drawView.addSubview(myView)

        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.duration = 2.0
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        animation.fromValue = 0.0
        animation.toValue = 1.0
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        shapeLayer.add(animation, forKey: nil)

        if Detector.isVertical {
            let animation2 = CABasicAnimation(keyPath: "position.y")
            animation2.duration = 2.0
            animation2.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animation2.toValue = shapeLayer2.position.y + 4 * 128
            animation2.fillMode = .forwards
            animation2.isRemovedOnCompletion = false

            shapeLayer2.add(animation2, forKey: nil)
        }
        else {
            let animation2 = CABasicAnimation(keyPath: "position.x")
            animation2.duration = 2.0
            animation2.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animation2.toValue = shapeLayer2.position.x + 5 * 128
            animation2.fillMode = .forwards
            animation2.isRemovedOnCompletion = false

            shapeLayer2.add(animation2, forKey: nil)
        }
        CATransaction.commit()
    }
    
    @IBAction func imageDirectionChanged(_ sender: UISwitch) {
        Detector.isVertical = sender.isOn
        animateDirection()
    }
}

