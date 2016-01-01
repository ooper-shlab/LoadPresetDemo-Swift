//
//  MainViewController.swift
//  LoadPresetDemo
//
//  Translated by OOPer in cooperation with shlab.jp, on 2016/1/1.
//
//
/*
     File: MainViewController.h
     File: MainViewController.m
 Abstract: The view controller for this app. Includes all the audio code.
  Version: 1.1

 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.

 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.

 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.

 Copyright (C) 2011 Apple Inc. All Rights Reserved.

*/

import UIKit
import AudioToolbox
import AVFoundation
import CoreAudio

private extension Int32 {
    var fc: String {
        return FourCharCode(bitPattern: self).fourCharString
    }
}

@objc(MainViewController)
class MainViewController: UIViewController {
    
    @IBOutlet var presetOneButton: UIButton!
    @IBOutlet var presetTwoButton: UIButton!
    @IBOutlet var lowNoteButton: UIButton!
    @IBOutlet var midNoteButton: UIButton!
    @IBOutlet var highNoteButton: UIButton!
    @IBOutlet var currentPresetLabel: UILabel!
    
    
    // some MIDI constants:
    private let kMIDIMessage_NoteOn: UInt32    = 0x9
    private let kMIDIMessage_NoteOff: UInt32   = 0x8
    
    private let kLowNote: UInt32 = 48
    private let kHighNote: UInt32 = 72
    private let kMidNote: UInt32 = 60
    
    // private class extension
    private var graphSampleRate: Float64 = 0.0
    private var processingGraph: AUGraph = nil
    private var samplerUnit: AudioUnit = nil
    private var ioUnit: AudioUnit = nil
    
    //MARK: -
    //MARK: Audio setup
    
    
    // Create an audio processing graph.
    private func createAUGraph() -> Bool {
        
        var samplerNode: AUNode = 0, ioNode: AUNode = 0
        
        // Specify the common portion of an audio unit's identify, used for both audio units
        // in the graph.
        var cd: AudioComponentDescription = AudioComponentDescription()
        cd.componentManufacturer     = kAudioUnitManufacturer_Apple
        cd.componentFlags            = 0
        cd.componentFlagsMask        = 0
        
        // Instantiate an audio processing graph
        var result: OSStatus = NewAUGraph(&processingGraph)
        assert(result == noErr, "Unable to create an AUGraph object. Error code: \(result) '\(result.fc)'")
        
        //Specify the Sampler unit, to be used as the first node of the graph
        cd.componentType = kAudioUnitType_MusicDevice
        cd.componentSubType = kAudioUnitSubType_Sampler
        
        // Add the Sampler unit node to the graph
        result = AUGraphAddNode(self.processingGraph, &cd, &samplerNode)
        assert(result == noErr, "Unable to add the Sampler unit to the audio processing graph. Error code: \(result) '\(result.fc)'")
        
        // Specify the Output unit, to be used as the second and final node of the graph
        cd.componentType = kAudioUnitType_Output
        cd.componentSubType = kAudioUnitSubType_RemoteIO
        
        // Add the Output unit node to the graph
        result = AUGraphAddNode(self.processingGraph, &cd, &ioNode)
        assert(result == noErr, "Unable to add the Output unit to the audio processing graph. Error code: \(result) '\(result.fc)'")
        
        // Open the graph
        result = AUGraphOpen(self.processingGraph)
        assert(result == noErr, "Unable to open the audio processing graph. Error code: \(result) '\(result.fc)'")
        
        // Connect the Sampler unit to the output unit
        result = AUGraphConnectNodeInput(self.processingGraph, samplerNode, 0, ioNode, 0)
        assert(result == noErr, "Unable to interconnect the nodes in the audio processing graph. Error code: \(result) '\(result.fc)'")
        
        // Obtain a reference to the Sampler unit from its node
        result = AUGraphNodeInfo(self.processingGraph, samplerNode, nil, &samplerUnit)
        assert(result == noErr, "Unable to obtain a reference to the Sampler unit. Error code: \(result) '\(result.fc)'")
        
        // Obtain a reference to the I/O unit from its node
        result = AUGraphNodeInfo(self.processingGraph, ioNode, nil, &ioUnit)
        assert(result == noErr, "Unable to obtain a reference to the I/O unit. Error code: \(result) '\(result.fc)'")
        
        return true
    }
    
    
    // Starting with instantiated audio processing graph, configure its
    // audio units, initialize it, and start it.
    private func configureAndStartAudioProcessingGraph(graph: AUGraph) {
        
        var framesPerSlice: UInt32 = 0
        var framesPerSlicePropertySize = UInt32(sizeofValue(framesPerSlice))
        let sampleRatePropertySize = UInt32(sizeofValue(self.graphSampleRate))
        
        var result = AudioUnitInitialize(self.ioUnit)
        assert(result == noErr, "Unable to initialize the I/O unit. Error code: \(result) '\(result.fc)'")
        
        // Set the I/O unit's output sample rate.
        result =    AudioUnitSetProperty(
            self.ioUnit,
            kAudioUnitProperty_SampleRate,
            kAudioUnitScope_Output,
            0,
            &graphSampleRate,
            sampleRatePropertySize
        )
        
        assert(result == noErr, "AudioUnitSetProperty (set Sampler unit output stream sample rate). Error code: \(result) '\(result.fc)'")
        
        // Obtain the value of the maximum-frames-per-slice from the I/O unit.
        result =    AudioUnitGetProperty(
            self.ioUnit,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &framesPerSlice,
            &framesPerSlicePropertySize
        )
        
        assert(result == noErr, "Unable to retrieve the maximum frames per slice property from the I/O unit. Error code: \(result) '\(result.fc)'")
        
        // Set the Sampler unit's output sample rate.
        result =    AudioUnitSetProperty(
            self.samplerUnit,
            kAudioUnitProperty_SampleRate,
            kAudioUnitScope_Output,
            0,
            &graphSampleRate,
            sampleRatePropertySize
        )
        
        assert(result == noErr, "AudioUnitSetProperty (set Sampler unit output stream sample rate). Error code: \(result) '\(result.fc)'")
        
        // Set the Sampler unit's maximum frames-per-slice.
        result =    AudioUnitSetProperty(
            self.samplerUnit,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &framesPerSlice,
            framesPerSlicePropertySize
        )
        
        assert(result == noErr, "AudioUnitSetProperty (set Sampler unit maximum frames per slice). Error code: \(result) '\(result.fc)'")
        
        
        if graph != nil {
            
            // Initialize the audio processing graph.
            result = AUGraphInitialize(graph)
            assert(result == noErr, "Unable to initialze AUGraph object. Error code: \(result) '\(result.fc)'")
            
            // Start the graph
            result = AUGraphStart(graph)
            assert(result == noErr, "Unable to start audio processing graph. Error code: \(result) '\(result.fc)'")
            
            // Print out the graph to the console
            CAShow(UnsafeMutablePointer<Void>(graph))
        }
    }
    
    
    // Load the Trombone preset
    @IBAction func loadPresetOne(_: AnyObject) {
        
        guard let presetURL = NSBundle.mainBundle().URLForResource("Trombone", withExtension: "aupreset") else {
            NSLog("COULD NOT GET PRESET PATH!")
            return
        }
        NSLog("Attempting to load preset '%@'\n", presetURL.description)
        self.currentPresetLabel.text = "Trombone"
        
        self.loadSynthFromPresetURL(presetURL)
    }
    
    // Load the Vibraphone preset
    @IBAction func loadPresetTwo(_: AnyObject) {
        
        guard let presetURL = NSBundle.mainBundle().URLForResource("Vibraphone", withExtension: "aupreset") else {
            NSLog("COULD NOT GET PRESET PATH!")
            return
        }
        NSLog("Attempting to load preset '%@'\n", presetURL.description)
        self.currentPresetLabel.text = "Vibraphone"
        
        self.loadSynthFromPresetURL(presetURL)
    }
    
    // Load a synthesizer preset file and apply it to the Sampler unit
    private func loadSynthFromPresetURL(presetURL: NSURL) -> OSStatus {
        
        var result = noErr
        
        // Read from the URL and convert into a CFData chunk
        guard let propertyResourceData = NSData(contentsOfURL: presetURL) else {
            
            fatalError("Unable to create data and properties from a preset.")
        }
        
        // Convert the data object into a property list
        var dataFormat: NSPropertyListFormat = NSPropertyListFormat.XMLFormat_v1_0
        do {
            var presetPropertyList = try NSPropertyListSerialization.propertyListWithData(propertyResourceData, options: [.Immutable], format: &dataFormat)
            
            // Set the class info property for the Sampler unit using the property list as the value.
            
            result = AudioUnitSetProperty(
                self.samplerUnit,
                kAudioUnitProperty_ClassInfo,
                kAudioUnitScope_Global,
                0,
                &presetPropertyList,
                UInt32(sizeof(CFPropertyListRef))
            )
            
        } catch _ as NSError {}
        
        return result
    }
    
    
    // Set up the audio session for this app.
    private func setupAudioSession() -> Bool {
        
        let mySession = AVAudioSession.sharedInstance()
        
        // Specify that this object is the delegate of the audio session, so that
        //    this object's endInterruption method will be invoked when needed.
        NSNotificationCenter.defaultCenter().addObserver(self,
            selector: "handleInterruption:",
            name: AVAudioSessionInterruptionNotification,
            object: mySession)
        
        // Assign the Playback category to the audio session. This category supports
        //    audio output with the Ring/Silent switch in the Silent position.
        do {
            try mySession.setCategory(AVAudioSessionCategoryPlayback)
        } catch let audioSessionError as NSError {
            NSLog("Error setting audio session category. Error: \(audioSessionError)")
            return false
        }
        
        // Request a desired hardware sample rate.
        self.graphSampleRate = 44100.0    // Hertz
        
        do {
            try mySession.setPreferredSampleRate(self.graphSampleRate)
        } catch let audioSessionError as NSError {
            NSLog("Error setting preferred hardware sample rate. Error: \(audioSessionError)")
            return false
        }
        
        // Activate the audio session
        do {
            try mySession.setActive(true)
        } catch let audioSessionError as NSError {
            NSLog("Error activating the audio session. Error: \(audioSessionError)")
            return false
        }
        
        // Obtain the actual hardware sample rate and store it for later use in the audio processing graph.
        self.graphSampleRate = mySession.sampleRate
        
        return true
    }
    
    
    //MARK: -
    //MARK: Audio control
    // Play the low note
    @IBAction func startPlayLowNote(_: AnyObject) {
        
        let noteNum = kLowNote
        let onVelocity: UInt32 = 127
        let noteCommand = 	kMIDIMessage_NoteOn << 4 | 0
        
        let result = MusicDeviceMIDIEvent(self.samplerUnit, UInt32(noteCommand), noteNum, onVelocity, 0)
        if result != noErr {
            
            NSLog("Unable to start playing the low note. Error code: \(result) '\(result.fc)'")
        }
    }
    
    // Stop the low note
    @IBAction func stopPlayLowNote(_: AnyObject) {
        
        let noteNum = kLowNote
        let noteCommand = 	kMIDIMessage_NoteOff << 4 | 0
        
        let result = MusicDeviceMIDIEvent (self.samplerUnit, noteCommand, noteNum, 0, 0)
        if result != noErr {
            
            NSLog("Unable to stop playing the low note. Error code: \(result) '\(result.fc)'")
        }
    }
    
    // Play the mid note
    @IBAction func startPlayMidNote(_: AnyObject) {
        
        let noteNum = kMidNote
        let onVelocity: UInt32 = 127
        let noteCommand = 	kMIDIMessage_NoteOn << 4 | 0
        
        let result = MusicDeviceMIDIEvent(self.samplerUnit, noteCommand, noteNum, onVelocity, 0)
        if result != noErr {
            
            NSLog("Unable to start playing the mid note. Error code: \(result) '\(result.fc)'")
        }
    }
    
    // Stop the mid note
    @IBAction func stopPlayMidNote(_: AnyObject) {
        
        let noteNum = kMidNote
        let noteCommand = 	kMIDIMessage_NoteOff << 4 | 0
        
        let result = MusicDeviceMIDIEvent(self.samplerUnit, noteCommand, noteNum, 0, 0)
        if result != noErr {
            
            NSLog("Unable to stop playing the mid note. Error code: \(result) '\(result.fc)'")
        }
    }
    
    // Play the high note
    @IBAction func startPlayHighNote(_: AnyObject) {
        
        let noteNum = kHighNote
        let onVelocity: UInt32 = 127
        let noteCommand = 	kMIDIMessage_NoteOn << 4 | 0
        
        let result = MusicDeviceMIDIEvent(self.samplerUnit, noteCommand, noteNum, onVelocity, 0)
        if result != noErr {
            
            NSLog("Unable to start playing the high note. Error code: \(result) '\(result.fc)'")
        }
    }
    
    // Stop the high note
    @IBAction func stopPlayHighNote(_: AnyObject) {
        
        let  noteNum = kHighNote
        let noteCommand = 	kMIDIMessage_NoteOff << 4 | 0
        
        let result = MusicDeviceMIDIEvent(self.samplerUnit, noteCommand, noteNum, 0, 0)
        if result != noErr {
            
            NSLog("Unable to stop playing the high note. Error code: \(result) '\(result.fc)'")
        }
    }
    
    // Stop the audio processing graph
    private func stopAudioProcessingGraph() {
        
        var result = noErr
        if self.processingGraph != nil {
            result = AUGraphStop(self.processingGraph)
        }
        assert(result == noErr, "Unable to stop the audio processing graph. Error code: \(result) '\(result.fc)'")
    }
    
    // Restart the audio processing graph
    private func restartAudioProcessingGraph() {
        
        var result = noErr
        if self.processingGraph != nil {
            result = AUGraphStart(self.processingGraph)
        }
        assert(result == noErr, "Unable to restart the audio processing graph. Error code: \(result) '\(result.fc)'")
    }
    
    
    //MARK: -
    //MARK: Audio session delegate methods
    
    @objc func handleInterruption(notification: NSNotification) {
        guard notification.name == AVAudioSessionInterruptionNotification else {return}
        let interruptionType = notification.userInfo![AVAudioSessionInterruptionTypeKey] as! UInt
        if interruptionType == AVAudioSessionInterruptionType.Began.rawValue {
            self.beginInterruption()
        } else if interruptionType == AVAudioSessionInterruptionType.Ended.rawValue {
            if let optionsInt = notification.userInfo![AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSessionInterruptionOptions(rawValue: optionsInt)
                self.endInterruptionWithOptions(options)
            }
        }
    }
    
    // Respond to an audio interruption, such as a phone call or a Clock alarm.
    private func beginInterruption() {
        
        // Stop any notes that are currently playing.
        self.stopPlayLowNote(self)
        self.stopPlayMidNote(self)
        self.stopPlayHighNote(self)
        
        // Interruptions do not put an AUGraph object into a "stopped" state, so
        //    do that here.
        self.stopAudioProcessingGraph()
    }
    
    
    // Respond to the ending of an audio interruption.
    private func endInterruptionWithOptions(options: AVAudioSessionInterruptionOptions) {
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch let endInterruptionError as NSError {
            
            NSLog("Unable to reactivate the audio session. Error: \(endInterruptionError)")
            return
        }
        
        if options.contains(.ShouldResume) {
            
            /*
            In a shipping application, check here to see if the hardware sample rate changed from
            its previous value by comparing it to graphSampleRate. If it did change, reconfigure
            the ioInputStreamFormat struct to use the new sample rate, and set the new stream
            format on the two audio units. (On the mixer, you just need to change the sample rate).
            
            Then call AUGraphUpdate on the graph before starting it.
            */
            
            self.restartAudioProcessingGraph()
        }
    }
    
    
    //MARK: - Application state management
    
    // The audio processing graph should not run when the screen is locked or when the app has
    //  transitioned to the background, because there can be no user interaction in those states.
    //  (Leaving the graph running with the screen locked wastes a significant amount of energy.)
    //
    // Responding to these UIApplication notifications allows this class to stop and restart the
    //    graph as appropriate.
    private func registerForUIApplicationNotifications() {
        
        let notificationCenter = NSNotificationCenter.defaultCenter()
        
        notificationCenter.addObserver(self,
            selector: "handleResigningActive:",
            name: UIApplicationWillResignActiveNotification,
            object: UIApplication.sharedApplication())
        
        notificationCenter.addObserver(self,
            selector: "handleBecomingActive:",
            name: UIApplicationDidBecomeActiveNotification,
            object: UIApplication.sharedApplication())
        
    }
    
    
    @objc func handleResigningActive(_: NSNotification) {
        
        self.stopPlayLowNote(self)
        self.stopPlayMidNote(self)
        self.stopPlayHighNote(self)
        self.stopAudioProcessingGraph()
    }
    
    
    @objc func handleBecomingActive(_: NSNotification) {
        
        self.restartAudioProcessingGraph()
    }
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: NSBundle?) {
        
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        // If object initialization fails, return immediately.
        
        // Set up the audio session for this app, in the process obtaining the
        // hardware sample rate for use in the audio processing graph.
        let audioSessionActivated = self.setupAudioSession()
        assert(audioSessionActivated, "Unable to set up audio session.")
        
        // Create the audio processing graph; place references to the graph and to the Sampler unit
        // into the processingGraph and samplerUnit instance variables.
        self.createAUGraph()
        self.configureAndStartAudioProcessingGraph(self.processingGraph)
        
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        // Load the Trombone preset so the app is ready to play upon launch.
        self.loadPresetOne(self)
        self.registerForUIApplicationNotifications()
    }
    
    //- (void) viewDidUnload {
    //
    //    self.currentPresetLabel = nil;
    //    self.presetOneButton    = nil;
    //	self.presetTwoButton    = nil;
    //	self.lowNoteButton      = nil;
    //	self.midNoteButton      = nil;
    //	self.highNoteButton     = nil;
    //
    //    [super viewDidUnload];
    //}
    
    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return .Portrait
    }
    override func preferredInterfaceOrientationForPresentation() -> UIInterfaceOrientation {
        return .Portrait
    }
    //- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    //
    //    // Return YES for supported orientations
    //    return (interfaceOrientation == UIInterfaceOrientationPortrait);
    //}
    
    override func didReceiveMemoryWarning() {
        
        // Releases the view if it doesn't have a superview.
        super.didReceiveMemoryWarning()
        
        // Release any cached data, images, etc that aren't in use.
    }
    
    
}