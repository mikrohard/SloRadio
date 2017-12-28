# SloRadio [![Download on the App Store](http://iphone.jernej.org/app_store.png)](https://itunes.apple.com/si/app/sloradio/id316264385?mt=8)

Simple radio player app using MobileVLCKit library. It uses a simple API to fetch & update Slovenian radio stations. It also allows the user to freely add/remove/move radio stations.

[![](http://iphone.jernej.org/sloradio/sloradio1_thumb.png)](http://iphone.jernej.org/sloradio/sloradio1.png)
[![](http://iphone.jernej.org/sloradio/sloradio2_thumb.png)](http://iphone.jernej.org/sloradio/sloradio2.png)
[![](http://iphone.jernej.org/sloradio/sloradio3_thumb.png)](http://iphone.jernej.org/sloradio/sloradio3.png)

## How to build

SloRadio depends on the MobileVLCKit framework. You can either compile it from source or download a precompiled version. Just drop a working version of "MobileVLCKit.framework" into the "Libraries" directory and you're ready to build SloRadio.

* Source: https://code.videolan.org/videolan/VLCKit
* Binary: http://nightlies.videolan.org/build/iOS

Note: In order for the sleep timer fade-out volume to work you will need to compile MobileVLCKit using a modified version of VLC (https://github.com/mikrohard/vlc/tree/audiounit_volume);

## License

This code is distributed under the terms and conditions of the [MIT license](LICENSE). 
