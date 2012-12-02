12.2.2012 - Bob Kressin
This project sets up basic Core Bluetooth communication between two iOS6 devices.  It is heavily based on Apple's "BTLE_Transfer" project found on the Apple Developer's portal.  I've made a couple of simple modifications to make it easier to play with.

This is the code shown off at iOSDevCampColorado on December 1st, 2012.  Simply compile and install on two iOS6 devices, choose one as the Central, one as the Slave, and watch the NSTimer fire every second to transfer battery percentage from one device to the other.  I've tried to add comments throughout the code with "BK" to note where I touched Apple's original source.

Enjoy!

- Bob
