//
//  DeviceViewController.swift
//  AndroidTool
//
//  Created by Morten Just Petersen on 4/22/15.
//  Copyright (c) 2015 Morten Just Petersen. All rights reserved.
//

import Cocoa
import AVFoundation

class DeviceViewController: NSViewController, NSPopoverDelegate, UserScriptDelegate, IOSRecorderDelegate {
    var device : Device!
    @IBOutlet weak var deviceNameField: NSTextField!
    @IBOutlet  var cameraButton: NSButton!
    @IBOutlet weak var deviceImage: NSImageView!
    @IBOutlet weak var progressBar: NSProgressIndicator!
    @IBOutlet weak var videoButton: NSButton!
    @IBOutlet weak var moreButton: NSButton!
    
    var restingButton : NSImage!
    
    
    @IBOutlet var scriptsPopover: NSPopover!
    
    @IBOutlet var previewPopover: NSPopover!
    
    @IBOutlet var previewView: NSView!
    
    
    var iosHelper : IOSDeviceHelper!
    var shellTasker : ShellTasker!
    var isRecording = false
    var moreOpen = false
    var moreShouldClose = false
    
    func takeScreenshot(){
        self.startProgressIndication()
        
        if device.deviceOS == DeviceOS.Android {
        
            ShellTasker(scriptFile: "takeScreenshotOfDeviceWithSerial").run(arguments: [device.adbIdentifier!]) { (output) -> Void in
                self.stopProgressIndication()
                Util().showNotification("Screenshot ready", moreInfo: "", sound: true)
            }
        }
            
        if device.deviceOS == DeviceOS.Ios {
            print("IOS screenshot")
            
            
            ShellTasker(scriptFile: "takeScreenshotOfDeviceWithUUID").run(arguments: [device.uuid!], isUserScript: false, isIOS: true, complete: { (output) -> Void in
                self.stopProgressIndication()
                Util().showNotification("Screenshot ready", moreInfo: "", sound: true)
            })
            
        }
    }
    
    @IBAction func cameraClicked(sender: NSButton) {
        takeScreenshot()
    }

    func userScriptEnded() {
        stopProgressIndication()
        Util().restartRefreshingDeviceList()
    }
    
    func userScriptStarted() {
        startProgressIndication()
        Util().stopRefreshingDeviceList()
    }
    
    func userScriptWantsSerial() -> String {
        return device.adbIdentifier!
    }
    
    func popoverDidClose(notification: NSNotification) {
        Util().restartRefreshingDeviceList()
        moreOpen = false
    }

    @IBAction func moreClicked(sender: NSButton) {
        Util().stopRefreshingDeviceList()
        if !moreOpen{
            moreOpen = true
            scriptsPopover.showRelativeToRect(sender.bounds, ofView: sender, preferredEdge: NSRectEdge(rawValue: 2)!)
            }
    }
    
    func openPreviewPopover(){
//        previewPopover.showRelativeToRect(videoButton.bounds, ofView: videoButton, preferredEdge: 2)
    }
    
    func closePreviewPopover(){
        previewPopover.close()
    }
    
    
    func iosRecorderFailed(title: String, message: String?) {
        let alert = NSAlert()
        alert.messageText = title
        alert.runModal()
     
        cameraButton.enabled = true
        videoButton.enabled = true
        isRecording = false
        self.videoButton.image = NSImage(named: "recordButtonWhite")
    }
    
    func iosRecorderDidEndPreparing() {
        videoButton.alphaValue = 1
        print("recorder did end preparing")
        self.videoButton.image = NSImage(named: "stopButton")
        self.videoButton.enabled = true
    }
    
    func iosRecorderDidStartPreparing(device: AVCaptureDevice) {
        print("recorder did start preparing")
    }
    
    func startRecording(){
        Util().stopRefreshingDeviceList()
        isRecording = true
        self.restingButton = self.videoButton.image
        cameraButton.enabled = false
        moreButton.enabled = false


        switch device.deviceOS! {
        case .Android:
            startRecordingOnAndroidDevice(restingButton!)
        case .Ios:
            // iOS starts recording 1 second delayed, so delaying the STOP button to signal this to the user
            openPreviewPopover()
            videoButton.alphaValue = 0.5
            startRecordingOnIOSDevice()
        }
    }
    
    func startRecordingOnIOSDevice(){
        iosHelper.toggleRecording(device.avDevice)
    }
    
    func startRecordingOnAndroidDevice(restingButton:NSImage){
        shellTasker = ShellTasker(scriptFile: "startRecordingForSerial")
        
        let scalePref = NSUserDefaults.standardUserDefaults().doubleForKey("scalePref")
        let bitratePref = Int(NSUserDefaults.standardUserDefaults().doubleForKey("bitratePref"))
        
        // get phone's resolution, multiply with user preference for screencap size (either 1 or lower)
        var res = device.resolution!
        
        if device.type == DeviceType.Phone {
            res = (device.resolution!.width*scalePref, device.resolution!.height*scalePref)
        }
        
        let args:[String] = [device.adbIdentifier!, "\(Int(res.width))", "\(Int(res.height))", "\(bitratePref)"]
        
        shellTasker.run(arguments: args) { (output) -> Void in
            
            print("-----")
            print(output)
            print("-----")
            
            self.startProgressIndication()
            self.cameraButton.enabled = true
            self.moreButton.enabled = true
            self.videoButton.image = restingButton
            let postProcessTask = ShellTasker(scriptFile: "postProcessMovieForSerial")
            let postArgs = ["\(self.device.adbIdentifier!)", "\(Int(res.width))", "\(Int(res.height))"]
            postProcessTask.run(arguments: args, complete: { (output) -> Void in
                Util().showNotification("Your recording is ready", moreInfo: "", sound: true)
                self.stopProgressIndication()
            })
        }
    
    }
    
    func iosRecorderDidFinish(outputFileURL: NSURL!) {
        NSWorkspace.sharedWorkspace().openFile(outputFileURL.path!)
        self.videoButton.image = restingButton
        
        Util().showNotification("Your recording is ready", moreInfo: "", sound: true)
        cameraButton.enabled = true
        
        let movPath = outputFileURL.path!
        let gifUrl = outputFileURL.URLByDeletingPathExtension
        let gifPath = "\(gifUrl?.path!).gif"
        let ffmpegPath = NSBundle.mainBundle().pathForResource("ffmpeg", ofType: "")!
        let scalePref = NSUserDefaults.standardUserDefaults().doubleForKey("scalePref")
        
        ShellTasker(scriptFile: "convertMovieFiletoGif").run(arguments: [ffmpegPath, movPath, gifPath, "\(scalePref)"], isUserScript: false, isIOS: false) { (output) -> Void in
            print("done converting to gif")
            self.stopProgressIndication()
        }
        
        // convert to gif shell args
        // $ffmpeg = $1
        // $inputFile = $2
        // $outputFile = $3
    }
    
    func stopRecording(){
        Util().restartRefreshingDeviceList()
        isRecording = false
        videoButton.alphaValue = 1

        switch device.deviceOS! {
        case .Android:
            shellTasker.stop() // terminates script and fires the closure in startRecordingForSerial
        case .Ios:
            iosHelper.toggleRecording(device.avDevice) // stops recording and fires delegate:
        }
    }
    
    @IBAction func videoClicked(sender: NSButton) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    init?(device _device:Device){
        device = _device
        super.init(nibName: "DeviceViewController", bundle: nil)
        setup()
    }
    
    override init?(nibName nibNameOrNil: String?, bundle nibBundleOrNil: NSBundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(){
//        println("setting up view for \(device.name!)")        
    }
    
    func startProgressIndication(){
        progressBar.usesThreadedAnimation = true
        progressBar.startAnimation(nil)
    }
    
    func stopProgressIndication(){
        progressBar.stopAnimation(nil)
    }
    
    override func awakeFromNib() {
        deviceNameField.stringValue = device.model!
        let brandName = device.brand!.lowercaseString
        deviceImage.image = NSImage(named: "logo\(brandName)")
        
        if device.isEmulator {
            cameraButton.enabled = false
            videoButton.enabled = false
            deviceNameField.stringValue = "Emulator"
        }
        
        // only enable video recording if we have resolution, which is a bit slow because it comes from a big call
        videoButton.enabled = false
        enableVideoButtonWhenReady()
        
        if device.deviceOS == DeviceOS.Ios {
            iosHelper = IOSDeviceHelper(recorderDelegate: self, forDevice:device.avDevice)
            moreButton.hidden = true
        }
        
    }
    
    func startWaitingForAndroidVideoReady(){
        if device.resolution != nil {
            print("not nil")
            videoButton.enabled = true
        } else {
            print("is nil")
            NSTimer.scheduledTimerWithTimeInterval(1, target: self, selector: "enableVideoButtonWhenReady", userInfo: nil, repeats: false)
        }
    }
        
    func enableVideoButtonWhenReady(){
        switch device.deviceOS! {
        case .Android:
            startWaitingForAndroidVideoReady()
        case .Ios:
            // videoButton.hidden = false
            print("showing video button for iOS")
            videoButton.enabled = true
        }
    }

    override func viewDidLoad() {
        if #available(OSX 10.10, *) {
            super.viewDidLoad()
        } else {
            // Fallback on earlier versions
        }
        // Do view setup here.
    }
}
