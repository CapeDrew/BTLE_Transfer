/*
 
 File: LEPeripheralViewController.m
 
 Abstract: Interface to allow the user to enter data that will be
 transferred to a version of the app in Central Mode, when it is brought
 close enough.
 
 Version: 1.0
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by
 Apple Inc. ("Apple") in consideration of your agreement to the
 following terms, and your use, installation, modification or
 redistribution of this Apple software constitutes acceptance of these
 terms.  If you do not agree with these terms, please do not use,
 install, modify or redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc.
 may be used to endorse or promote products derived from the Apple
 Software without specific prior written permission from Apple.  Except
 as expressly stated in this notice, no other rights or licenses, express
 or implied, are granted by Apple herein, including but not limited to
 any patent rights that may be infringed by your derivative works or by
 other works in which the Apple Software may be incorporated.
 
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
 
 Copyright (C) 2012 Apple Inc. All Rights Reserved.
 
 */

#import "BTLEPeripheralViewController.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "TransferService.h"

#define kSendDataInterval   1.0                         // BK - Let's send data every second when connected

@interface BTLEPeripheralViewController () <CBPeripheralManagerDelegate, UITextViewDelegate>
@property (strong, nonatomic) IBOutlet UITextView       *textView;
@property (strong, nonatomic) IBOutlet UISwitch         *advertisingSwitch;
@property (strong, nonatomic) CBPeripheralManager       *peripheralManager;
@property (strong, nonatomic) CBMutableCharacteristic   *transferCharacteristic;
@property (strong, nonatomic) NSData                    *dataToSend;
@property (nonatomic, readwrite) NSInteger              sendDataIndex;

// BK
@property (strong, nonatomic) IBOutlet UILabel          *batteryLabel;
@property (strong, nonatomic) NSTimer                   *sendTimer;

@end



// BK - Apple set this to 20, the maximum payload size.
#define NOTIFY_MTU      20

@implementation BTLEPeripheralViewController

#pragma mark - View Lifecycle
- (void)viewDidLoad
{
    [super viewDidLoad];

    // Start up the CBPeripheralManager
    _peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil];
}

- (void)viewWillDisappear:(BOOL)animated
{
    // Don't keep it going while we're not showing.
    // BK - Actually, we always want to advertise.  Burn that battery!
    //[self.peripheralManager stopAdvertising];

    [super viewWillDisappear:animated];
}

#pragma mark - Peripheral Methods
/** Required protocol method.  A full app should take care of all the possible states,
 *  but we're just waiting for  to know when the CBPeripheralManager is ready
 */
- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral
{
    // Opt out from any other state
    if (peripheral.state != CBPeripheralManagerStatePoweredOn) {
        return;
    }
    
    // We're in CBPeripheralManagerStatePoweredOn state...
    NSLog(@"self.peripheralManager powered on.");
    
    // ... so build our service.
    
    // Start with the CBMutableCharacteristic
    self.transferCharacteristic = [[CBMutableCharacteristic alloc] initWithType:[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_UUID]
                                                                      properties:CBCharacteristicPropertyNotify
                                                                           value:nil
                                                                     permissions:CBAttributePermissionsReadable];

    // Then the service
    CBMutableService *transferService = [[CBMutableService alloc] initWithType:[CBUUID UUIDWithString:TRANSFER_SERVICE_UUID]
                                                                        primary:YES];
    
    // Add the characteristic to the service
    transferService.characteristics = @[self.transferCharacteristic];
    
    // And add it to the peripheral manager
    [self.peripheralManager addService:transferService];
    
    // BK - since we just want to start advertising right away, let's do that here, after we determine that the peripheralManager is good to go.
    [self.peripheralManager startAdvertising:@{ CBAdvertisementDataServiceUUIDsKey : @[[CBUUID UUIDWithString:TRANSFER_SERVICE_UUID]] }];

}


/** Catch when someone subscribes to our characteristic, then start sending them data
 */
- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didSubscribeToCharacteristic:(CBCharacteristic *)characteristic
{
    NSLog(@"Central subscribed to characteristic");
    
    // Get the data
    // BK - Apple used this originally to send text.  We just want to send battery percentage.  I kept the view and just hid it for now.
    //self.dataToSend = [self.textView.text dataUsingEncoding:NSUTF8StringEncoding];
    [self.textView setHidden:YES];
    
    // BK - Fire up a timer that will send data at regular intervals.
    self.sendTimer = [NSTimer scheduledTimerWithTimeInterval:kSendDataInterval target:self selector:@selector(transferDataBasedOnTimer:) userInfo:nil repeats:NO];
    
    // BK - Get the battery percentage
    [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
    NSNumber *batteryLevel = [NSNumber numberWithFloat:(100*[[UIDevice currentDevice] batteryLevel])];
    NSString *batteryLevelString = [NSString stringWithFormat:@"%@%%", batteryLevel];
    
    // BK - Show it locally.  I display "Waiting for Connection" until the connection occurs, then update the label.
    [self.batteryLabel setText:batteryLevelString];
    
    // BK - tee it up.
    self.dataToSend = [batteryLevelString dataUsingEncoding:NSUTF8StringEncoding];
    
    // Reset the index
    self.sendDataIndex = 0;
    
    // Start sending
    [self sendData];
}


/** Recognise when the central unsubscribes
 */
- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic
{
    NSLog(@"Central unsubscribed from characteristic");
    
    // BK - Update our battery label to show we have no connection
    [self.batteryLabel setText:@"Waiting for Connection"];
    
    // BK - Kill our timer
    [self.sendTimer invalidate];
    self.sendTimer =  nil;
    
}

// BK - I added this method for sending timed data
- (void)transferDataBasedOnTimer:(NSTimer *)aTimer {
    
    // BK - Get the battery percentage
    [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
    NSNumber *batteryLevel = [NSNumber numberWithFloat:(100*[[UIDevice currentDevice] batteryLevel])];
    NSString *batteryLevelString = [NSString stringWithFormat:@"%@%%", batteryLevel];
    
    // BK - Show it locally.  I display "Waiting for Connection" until the connection occurs, then update the label.
    [self.batteryLabel setText:batteryLevelString];
    
    // BK - tee it up.
    self.dataToSend = [batteryLevelString dataUsingEncoding:NSUTF8StringEncoding];
    
    // Reset the index
    self.sendDataIndex = 0;
    
    // Start sending
    [self sendData];
    
    // Do it all over again.
    [self.sendTimer invalidate];
    self.sendTimer = nil;
    self.sendTimer = [NSTimer scheduledTimerWithTimeInterval:kSendDataInterval target:self selector:@selector(transferDataBasedOnTimer:) userInfo:nil repeats:NO];
    
}

/** Sends the next amount of data to the connected central
 */
- (void)sendData
{
    // First up, check if we're meant to be sending an EOM
    static BOOL sendingEOM = NO;
    
    if (sendingEOM) {
        
        // send it
        BOOL didSend = [self.peripheralManager updateValue:[@"EOM" dataUsingEncoding:NSUTF8StringEncoding] forCharacteristic:self.transferCharacteristic onSubscribedCentrals:nil];
        
        // Did it send?
        if (didSend) {
            
            // It did, so mark it as sent
            sendingEOM = NO;
            
            NSLog(@"Sent: EOM");
        }
        
        // It didn't send, so we'll exit and wait for peripheralManagerIsReadyToUpdateSubscribers to call sendData again
        return;
    }
    
    // We're not sending an EOM, so we're sending data
    
    // Is there any left to send?
    
    if (self.sendDataIndex >= self.dataToSend.length) {
        
        // No data left.  Do nothing
        return;
    }
    
    // There's data left, so send until the callback fails, or we're done.
    
    BOOL didSend = YES;
    
    while (didSend) {
        
        // Make the next chunk
        
        // Work out how big it should be
        NSInteger amountToSend = self.dataToSend.length - self.sendDataIndex;
        
        // Can't be longer than 20 bytes
        if (amountToSend > NOTIFY_MTU) amountToSend = NOTIFY_MTU;
        
        // Copy out the data we want
        NSData *chunk = [NSData dataWithBytes:self.dataToSend.bytes+self.sendDataIndex length:amountToSend];
        
        // Send it
        didSend = [self.peripheralManager updateValue:chunk forCharacteristic:self.transferCharacteristic onSubscribedCentrals:nil];
        
        // If it didn't work, drop out and wait for the callback
        if (!didSend) {
            return;
        }
        
        NSString *stringFromData = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
        NSLog(@"Sent: %@", stringFromData);
        
        // It did send, so update our index
        self.sendDataIndex += amountToSend;
        
        // Was it the last one?
        if (self.sendDataIndex >= self.dataToSend.length) {
            
            // It was - send an EOM
            
            // Set this so if the send fails, we'll send it next time
            sendingEOM = YES;
            
            // Send it
            BOOL eomSent = [self.peripheralManager updateValue:[@"EOM" dataUsingEncoding:NSUTF8StringEncoding] forCharacteristic:self.transferCharacteristic onSubscribedCentrals:nil];
            
            if (eomSent) {
                // It sent, we're all done
                sendingEOM = NO;
                
                NSLog(@"Sent: EOM");
            }
            
            return;
        }
    }
}


/** This callback comes in when the PeripheralManager is ready to send the next chunk of data.
 *  This is to ensure that packets will arrive in the order they are sent
 */
- (void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)peripheral
{
    // Start sending again
    [self sendData];
}

#pragma mark - TextView Methods
/** This is called when a change happens, so we know to stop advertising
 */
- (void)textViewDidChange:(UITextView *)textView
{
    // If we're already advertising, stop
    if (self.advertisingSwitch.on) {
        [self.advertisingSwitch setOn:NO];
        [self.peripheralManager stopAdvertising];
    }
}


/** Adds the 'Done' button to the title bar
 */
- (void)textViewDidBeginEditing:(UITextView *)textView
{
    // We need to add this manually so we have a way to dismiss the keyboard
    UIBarButtonItem *rightButton = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonSystemItemDone target:self action:@selector(dismissKeyboard)];
    self.navigationItem.rightBarButtonItem = rightButton;
}


/** Finishes the editing */
- (void)dismissKeyboard
{
    [self.textView resignFirstResponder];
    self.navigationItem.rightBarButtonItem = nil;
}



#pragma mark - Switch Methods
/** Start advertising
 */
- (IBAction)switchChanged:(id)sender
{
    if (self.advertisingSwitch.on) {
        // All we advertise is our service's UUID
        [self.peripheralManager startAdvertising:@{ CBAdvertisementDataServiceUUIDsKey : @[[CBUUID UUIDWithString:TRANSFER_SERVICE_UUID]] }];
    }
    
    else {
        [self.peripheralManager stopAdvertising];
    }
}


@end
