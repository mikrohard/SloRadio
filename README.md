# SloRadio [![Download on the App Store](http://iphone.jernej.org/app_store.png)](https://itunes.apple.com/si/app/sloradio/id316264385?mt=8)

Simple radio player app with its own audio player built on the FFmpeg libraries (and AVPlayer for HLS streams). It uses a simple API to fetch & update Slovenian radio stations. It also allows the user to freely add/remove/move radio stations.

[![](http://iphone.jernej.org/sloradio/sloradio1_thumb.png)](http://iphone.jernej.org/sloradio/sloradio1.png)
[![](http://iphone.jernej.org/sloradio/sloradio2_thumb.png)](http://iphone.jernej.org/sloradio/sloradio2.png)
[![](http://iphone.jernej.org/sloradio/sloradio3_thumb.png)](http://iphone.jernej.org/sloradio/sloradio3.png)

## How to build

SloRadio plays streams with the FFmpeg libraries, which are built from source the first time you build the app (Scripts/build-ffmpeg.sh, run by the scheme's pre-action; it takes about a minute). The build needs the Xcode command line tools and downloads the FFmpeg source from https://ffmpeg.org. The result is placed in "Libraries/FFmpeg", after that just build and run.

FFmpeg is used under the LGPLv2.1 and linked dynamically.

## License

This code is distributed under the terms and conditions of the [MIT license](LICENSE). 
