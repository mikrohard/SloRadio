# SloRadio [![Download on the App Store](http://iphone.jernej.org/app_store.png)](https://itunes.apple.com/si/app/sloradio/id316264385?mt=8)

Simple radio player app using MobileVLCKit library. It uses a simple API to fetch & update Slovenian radio stations. It also allows the user to freely add/remove/move radio stations.

[![](http://iphone.jernej.org/sloradio/sloradio1_thumb.png)](http://iphone.jernej.org/sloradio/sloradio1.png)
[![](http://iphone.jernej.org/sloradio/sloradio2_thumb.png)](http://iphone.jernej.org/sloradio/sloradio2.png)
[![](http://iphone.jernej.org/sloradio/sloradio3_thumb.png)](http://iphone.jernej.org/sloradio/sloradio3.png)

## How to build

SloRadio depends on the MobileVLCKit framework. You can either compile it from source or download a precompiled version. Just drop a working version of "MobileVLCKit.framework" into the "Libraries" directory and you're ready to build SloRadio.

* Source: http://git.videolan.org/?p=vlc-bindings/VLCKit.git
* Binary: http://nightlies.videolan.org/build/ios/

Note: In order for the sleep timer fade-out volume to work the current MobileVLCKit needs to be compiled with the "--enable-audioqueue" option.

## License

This code is distributed under the terms and conditions of the [MIT license](LICENSE). 
