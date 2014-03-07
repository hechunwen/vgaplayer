//  VGAPlayer
//

package {

import flash.display.Sprite;
import flash.display.DisplayObject;
import flash.display.LoaderInfo;
import flash.display.StageDisplayState;
import flash.display.StageScaleMode;
import flash.display.StageAlign;
import flash.events.Event;
import flash.events.KeyboardEvent;
import flash.events.MouseEvent;
import flash.events.FullScreenEvent;
import flash.events.NetStatusEvent;
import flash.events.AsyncErrorEvent;
import flash.media.Video;
import flash.media.SoundTransform;
import flash.net.NetConnection;
import flash.net.NetStream;
import flash.ui.Keyboard;
import flash.geom.Point;

//  Main 
//
public class Main extends Sprite
{
  private var _params:Params;
  private var _video:Video;
  private var _overlay:VideoOverlay;
  private var _control:ControlBar;
  private var _debugdisp:DebugDisplay;

  private var _connection:NetConnection;
  private var _stream:NetStream;
  private var _videosize:Point;
  private var _started:Boolean;

  // Main()
  public function Main()
  {
    var info:LoaderInfo = LoaderInfo(this.root.loaderInfo);
    _params = new Params(info.loaderURL, info.parameters);
    
    stage.color = _params.bgColor;
    stage.scaleMode = StageScaleMode.NO_SCALE;
    stage.align = StageAlign.TOP_LEFT;

    _video = new Video();
    addChild(_video);

    _overlay = new VideoOverlay();
    _overlay.buttonBgColor = _params.buttonBgColor;
    _overlay.buttonFgColor = _params.buttonFgColor;
    _overlay.addEventListener(MouseEvent.CLICK, onOverlayClick);
    addChild(_overlay);

    _control = new ControlBar(_params.fullscreen);
    _control.status.bgColor = _params.buttonBgColor;
    _control.status.fgColor = _params.buttonFgColor;
    _control.status.hiColor = _params.buttonHiColor;
    _control.playButton.bgColor = _params.buttonBgColor;
    _control.playButton.fgColor = _params.buttonFgColor;
    _control.playButton.hiColor = _params.buttonHiColor;
    _control.playButton.borderColor = _params.buttonBorderColor;
    _control.playButton.addEventListener(MouseEvent.CLICK, onPlayPauseClick);
    _control.volumeSlider.bgColor = _params.buttonBgColor;
    _control.volumeSlider.fgColor = _params.buttonFgColor;
    _control.volumeSlider.hiColor = _params.buttonHiColor;
    _control.volumeSlider.addEventListener(Slider.CLICK, onVolumeSliderClick);
    _control.volumeSlider.addEventListener(Slider.CHANGED, onVolumeSliderChanged);
    if (_control.fsButton != null) {
      _control.fsButton.bgColor = _params.buttonBgColor;
      _control.fsButton.fgColor = _params.buttonFgColor;
      _control.fsButton.hiColor = _params.buttonHiColor;
      _control.fsButton.borderColor = _params.buttonBorderColor;
      _control.fsButton.toFullscreen = (stage.displayState == StageDisplayState.NORMAL);
      _control.fsButton.addEventListener(MouseEvent.CLICK, onFullscreenClick);
    }
    addChild(_control);
    
    _debugdisp = new DebugDisplay();
    _debugdisp.visible = _params.debug;
    addChild(_debugdisp);

    stage.addEventListener(Event.RESIZE, onResize);
    stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
    stage.addEventListener(FullScreenEvent.FULL_SCREEN, onFullScreen);
    stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
    stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
    resize();

    log("FlashVars:", expandAttrs(info.parameters));
    log("url:", _params.url);
    log("fullscreen:", _params.fullscreen);
    log("bufferTime:", _params.bufferTime);
    log("bufferTimeMax:", _params.bufferTimeMax);
    log("maxPauseBufferTime:", _params.maxPauseBufferTime);

    _connection = new NetConnection();
    _connection.addEventListener(NetStatusEvent.NET_STATUS, onNetStatusEvent);
    _connection.addEventListener(AsyncErrorEvent.ASYNC_ERROR, onAsyncErrorEvent);
    connect();
  }

  private function log(... args):void
  {
    var x:String = "";
    for each (var a:Object in args) {
      if (x.length != 0) x += " ";
      x += a;
    }
    _debugdisp.writeLine(x);
    trace(x);
  }

  private function expandAttrs(obj:Object):String
  {
    var x:String = null;
    for (var key:Object in obj) {
      var value:Object = obj[key];
      if (x == null) {
	x = key+"="+value;
      } else {
	x += ", "+key+"="+value;
      }
    }
    return x;
  }

  private function onResize(e:Event):void
  {
    resize();
  }

  private function onFullScreen(e:FullScreenEvent):void
  {
    _control.fsButton.toFullscreen = !e.fullScreen;
  }

  private function onEnterFrame(e:Event):void
  {
    update();
  }

  private function onMouseMove(e:MouseEvent):void 
  {
    _control.show();
  }

  private function onKeyDown(e:KeyboardEvent):void 
  {
    switch (e.keyCode) {
    case Keyboard.ESCAPE:	// Esc
    case 68:			// D
      _debugdisp.visible = !_debugdisp.visible;
      break;
    case Keyboard.SPACE:
      setPlayState(!_started);
      break;
    }
  }

  private function onNetStatusEvent(ev:NetStatusEvent):void
  {
    log("onNetStatusEvent:", expandAttrs(ev.info));
    switch (ev.info.code) {
    case "NetConnection.Connect.Failed":
    case "NetConnection.Connect.Rejected":
    case "NetConnection.Connect.InvalidApp":
      _control.autohide = false;
      _control.status.text = "Failed";
      break;
      
    case "NetConnection.Connect.Success":
      var nc:Netconnection = ev.target;
      _stream = new NetStream(nc);
      _stream.addEventListener(NetStatusEvent.NET_STATUS, onNetStatusEvent);
      _stream.addEventListener(AsyncErrorEvent.ASYNC_ERROR, onAsyncErrorEvent);
      _stream.client = new Object();
      _stream.client.onMetaData = onMetaData;
      _stream.client.onCuePoint = onCuePoint;
      _stream.client.onPlayStatus = onPlayStatus;
      _stream.bufferTime = _params.bufferTime;
      _stream.bufferTimeMax = _params.bufferTimeMax;
      _stream.maxPauseBufferTime = _params.maxPauseBufferTime;
      _video.attachNetStream(_stream);
      _updateVolume(_control.volumeSlider);
      _control.autohide = false;
      _control.status.text = "Connected";
      _started = false;
      startPlaying();
      break;

    case "NetConnection.Connect.Closed":
      stopPlaying();
      _started = false;
      _video.attachNetStream(null);
      _stream.removeEventListener(NetStatusEvent.NET_STATUS, onNetStatusEvent);
      _stream.removeEventListener(AsyncErrorEvent.ASYNC_ERROR, onAsyncErrorEvent);
      _stream.client = null;
      _stream = null;
      _control.autohide = false;
      _control.status.text = "Disconnected";
      break;

    case "NetStream.Play.Start":
      _started = true;
      _control.autohide = false;
      _control.playButton.toPlay = false;
      _control.status.text = "Buffering...";
      break;

    case "NetStream.Play.Stop":
    case "NetStream.Play.Complete":
    case "NetStream.Buffer.Flush":
      _started = false;
      _control.autohide = false;
      _control.playButton.toPlay = true;
      _control.status.text = "Stopped";
      break;

    case "NetStream.Buffer.Empty":
      _control.autohide = false;
      _control.status.text = "Buffering...";
      break;
    case "NetStream.Buffer.Full":
      _started = true;
      _control.autohide = true;
      _control.status.text = "Playing";
      break;
    }
  }

  private function onMetaData(info:Object):void
  {
    log("onMetaData:", expandAttrs(info));
    _videosize = new Point(info.width, info.height);
    resize();
  }

  private function onCuePoint(info:Object):void
  {
    log("onCuePoint:", expandAttrs(info));
  }

  private function onPlayStatus(info:Object):void
  {
    log("onPlayStatus:", expandAttrs(info));
  }

  private function onAsyncErrorEvent(ev:AsyncErrorEvent):void
  {
    log("onAsyncErrorEvent:", ev.error);
  }

  private function onOverlayClick(e:MouseEvent):void 
  {  
    var overlay:VideoOverlay = VideoOverlay(e.target);
    var playing:Boolean = !_started;
    overlay.show(playing);
    setPlayState(playing);
  }

  private function onPlayPauseClick(e:Event):void
  {
    var button:PlayPauseButton = PlayPauseButton(e.target);
    setPlayState(button.toPlay);
  }

  private function _updateVolume(slider:VolumeSlider):void
  {
    if (_stream != null) {
      var transform:SoundTransform = 
	new SoundTransform((slider.muted)? 0 : slider.value);
      _stream.soundTransform = transform;
    }
  }

  private function onVolumeSliderClick(e:Event):void
  {
    var slider:VolumeSlider = VolumeSlider(e.target);
    slider.muted = !slider.muted;
    _updateVolume(slider);
  }
  
  private function onVolumeSliderChanged(e:Event):void
  {
    var slider:VolumeSlider = VolumeSlider(e.target);
    _updateVolume(slider);
  }

  private function onFullscreenClick(e:Event):void
  {
    var button:FullscreenButton = FullscreenButton(e.target);
    stage.displayState = ((button.toFullscreen)? 
			  StageDisplayState.FULL_SCREEN : 
			  StageDisplayState.NORMAL);
  }

  public function connect():void
  {
    if (_params.rtmpURL != null && !_connection.connected) {
      log("Connecting:", _params.rtmpURL);
      _control.status.text = "Connecting...";
      _connection.connect(_params.rtmpURL);
    }
  }

  public function startPlaying():void
  {
    if (_stream != null && _params.streamPath != null) {
      log("Playing:", _params.streamPath);
      _control.status.text = "Starting...";
      _stream.play(_params.streamPath);
    }
  }

  public function stopPlaying():void
  {
    if (_stream != null && _params.streamPath != null) {
      log("Stopping");
      _control.status.text = "Stopping...";
      _stream.close();
    }
  }

  public function setPlayState(playing:Boolean):void
  {
    log("setPlayState:", playing);
    if (playing) {
      if (_started) {

      } else if (_connection.connected) {
	startPlaying();
      } else {
	connect();
      }
    } else {
      if (_started) {
	stopPlaying();
      }
    }
  }

  public function resize():void
  {
    log("resize:", stage.stageWidth+","+stage.stageHeight);
    x = 0;
    y = 0;

    if (_videosize != null) {
      var r:Number = Math.min((stage.stageWidth / _videosize.x),
			      (stage.stageHeight / _videosize.y));
      _video.width = _videosize.x*r;
      _video.height = _videosize.y*r;
      _video.x = (stage.stageWidth - _video.width)/2;
      _video.y = (stage.stageHeight - _video.height)/2;
    }

    _overlay.resize(stage.stageWidth, stage.stageHeight);
    _overlay.x = 0;
    _overlay.y = 0;

    _control.resize(stage.stageWidth, 28);
    _control.x = 0;
    _control.y = stage.stageHeight-_control.height;

    _debugdisp.resize(stage.stageWidth, stage.stageHeight-_control.height);
    _debugdisp.x = 0;
    _debugdisp.y = 0;
  }

  public function update():void
  {
    _overlay.update();
    _control.update();
    if (_debugdisp.visible && _stream != null) {
      _debugdisp.update(_stream);
    }
  }

}

} // package

/// Private classed below.

import flash.display.Sprite;
import flash.events.Event;
import flash.events.MouseEvent;
import flash.text.TextField;
import flash.text.TextFieldType;
import flash.text.TextFieldAutoSize;
import flash.net.NetStream;
import flash.net.NetStreamInfo;
import flash.ui.Keyboard;
import flash.utils.getTimer;

//  Params
//  Object to hold the parameters given by FlashVars.
//
class Params
{
  public var debug:Boolean = false;
  public var url:String = null;
  public var bufferTime:Number = 1.0;
  public var bufferTimeMax:Number = 1.0;
  public var maxPauseBufferTime:Number = 30.0;
  public var fullscreen:Boolean = false;
  public var rtmpURL:String = null;
  public var streamPath:String = null;

  public var bgColor:uint = 0x000000;
  public var buttonBgColor:uint = 0x448888ff;
  public var buttonFgColor:uint = 0xcc888888;
  public var buttonHiColor:uint = 0xffeeeeee;
  public var buttonBorderColor:uint = 0x88ffffff;
  public var volumeMutedColor:uint = 0xffff0000;

  public function Params(baseurl:String, obj:Object)
  {
    var i:int;

    if (obj != null) {
      // debug
      if (obj.debug) {
	debug = (parseInt(obj.debug) != 0);
      }
      // url
      if (obj.url) {
	url = obj.url;
      }
      // bufferTime
      if (obj.bufferTime) {
	bufferTime = parseFloat(obj.bufferTime);
	bufferTimeMax = bufferTime;
	maxPauseBufferTime = bufferTime;
      }
      // bufferTimeMax
      if (obj.bufferTimeMax) {
	bufferTimeMax = parseFloat(obj.bufferTimeMax);
      }
      // maxPauseBufferTime
      if (obj.maxPauseBufferTime) {
	maxPauseBufferTime = parseFloat(obj.maxPauseBufferTime);
      }
      // fullscreen
      if (obj.fullscreen) {
	fullscreen = (parseInt(obj.fullscreen) != 0);
      }

      // bgColor
      if (obj.bgColor) {
	bgColor = parseColor(obj.bgColor);
      }
      // buttonBgColor
      if (obj.buttonBgColor) {
	buttonBgColor = parseColor(obj.buttonBgColor);
      }
      // buttonFgColor
      if (obj.buttonFgColor) {
	buttonFgColor = parseColor(obj.buttonFgColor);
      }
      // buttonHiColor
      if (obj.buttonHiColor) {
	buttonHiColor = parseColor(obj.buttonHiColor);
      }
      // buttonBorderColor
      if (obj.buttonBorderColor) {
	buttonBorderColor = parseColor(obj.buttonBorderColor);
      }
      // volumeMutedColor
      if (obj.volumeMutedColor) {
	volumeMutedColor = parseColor(obj.volumeMutedColor);
      }
    }

    if (url != null) {
      if (url.substr(0, 1) == "/") {
	// if url starts with "/", it means a relative url.
	i = baseurl.indexOf("://");
	if (0 < i) {
	  baseurl = baseurl.substring(i+3);
	  i = baseurl.indexOf("/");
	  if (i < 0) {
	    i = baseurl.length;
	  }
	  url = "rtmp://"+baseurl.substr(0, i)+url;
	}
      }
      i = url.lastIndexOf("/");
      rtmpURL = url.substr(0, i);
      streamPath = url.substr(i+1);
    }
  }

  private function parseColor(v:String):uint
  {
    if (v.substr(0, 1) == "#") {
      v = v.substr(1);
    }
    return parseInt(v, 16);
  }
}


//  Control
//  Base class for buttons/sliders.
//
class Control extends Sprite
{
  public var bgColor:uint = 0x448888ff;
  public var fgColor:uint = 0xcc888888;
  public var hiColor:uint = 0xffeeeeee;
  public var borderColor:uint = 0x88ffffff;

  private var _width:int;
  private var _height:int;

  private var _mousedown:Boolean;
  private var _mouseover:Boolean;
  private var _invalidated:Boolean;

  public function Control()
  {
    addEventListener(Event.ADDED_TO_STAGE, onAdded);
    addEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
    addEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
  }

  public function get pressed():Boolean
  {
    return _mouseover && _mousedown;
  }

  public function get highlit():Boolean
  {
    return _mouseover || _mousedown;
  }
  
  private function onAdded(e:Event):void 
  {
    stage.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
    stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
  }

  protected virtual function onMouseDown(e:MouseEvent):void 
  {
    if (_mouseover) {
      _mousedown = true;
      _invalidated = true;
    }
  }

  protected virtual function onMouseUp(e:MouseEvent):void 
  {
    if (_mousedown) {
      _mousedown = false;
      _invalidated = true;
    }
  }

  protected virtual function onMouseOver(e:MouseEvent):void 
  {
    _mouseover = true;
    _invalidated = true;
  }

  protected virtual function onMouseOut(e:MouseEvent):void 
  {
    _mouseover = false;
    _invalidated = true;
  }

  protected function invalidate():void
  {
    _invalidated = true;
  }

  public virtual function resize(w:int, h:int):void
  {
    _width = w;
    _height = h;
    repaint();
  }

  public virtual function repaint():void
  {
    graphics.clear();
    graphics.beginFill(bgColor, (bgColor>>>24)/255);
    graphics.drawRect(0, 0, _width, _height);
    graphics.endFill();
  }

  public virtual function update():void
  {
    if (_invalidated) {
      _invalidated = false;
      repaint();
    }
  }
}


//  Button
//  Generic button class.
//  
class Button extends Control
{
  public function get buttonSize():int
  {
    return Math.min(width, height);
  }

  public override function repaint():void
  {
    super.repaint();

    if (highlit) {
      graphics.lineStyle(0, borderColor, (borderColor>>>24)/255);
      graphics.drawRect(0, 0, width, height);
    }
  }
}


//  Slider
//  Generic slider class.
// 
class Slider extends Button
{
  public static const CLICK:String = "Slider.Click";
  public static const CHANGED:String = "Slider.Changed";

  public var minDelta:int = 4;

  private var _x0:int;
  private var _y0:int;
  private var _changing:Boolean;

  protected override function onMouseDown(e:MouseEvent):void 
  {
    super.onMouseDown(e);
    addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
    _x0 = e.localX;
    _y0 = e.localY;
    _changing = false;
  }

  protected override function onMouseUp(e:MouseEvent):void 
  {
    if (!_changing && pressed) {
      dispatchEvent(new Event(CLICK));
    }
    removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
    super.onMouseUp(e);
  }

  protected virtual function onMouseMove(e:MouseEvent):void 
  {
    if (_changing) {
      onMouseDrag(e);
    } else {
      if (minDelta <= Math.abs(e.localX-_x0) ||
	  minDelta <= Math.abs(e.localY-_y0)) {
	_changing = true;
      }
    }
  }

  protected virtual function onMouseDrag(e:MouseEvent):void
  {
  }
}


//  ControlBar
//  Bar shown at the bottom of screen containing buttons, etc.
//
class ControlBar extends Sprite
{
  public var margin:int = 4;
  public var fadeDuration:int = 1000;

  public var status:StatusDisplay;
  public var playButton:PlayPauseButton;
  public var volumeSlider:VolumeSlider;
  public var fsButton:FullscreenButton;

  private var _autohide:Boolean;
  private var _timeout:int;

  public function ControlBar(fullscreen:Boolean=false)
  {
    _timeout = -fadeDuration;

    playButton = new PlayPauseButton();
    playButton.toPlay = true;
    addChild(playButton);

    volumeSlider = new VolumeSlider();
    volumeSlider.value = 1.0;
    addChild(volumeSlider);

    if (fullscreen) {
      fsButton = new FullscreenButton();
      addChild(fsButton);
    }

    status = new StatusDisplay();
    addChild(status);
  }

  public function get autohide():Boolean
  {
    return _autohide;
  }

  public function set autohide(value:Boolean):void
  {
    _autohide = value;
    show();
  }

  public function show(duration:int=2000):void
  {
    _timeout = getTimer()+duration;
  }

  public function resize(w:int, h:int):void
  {
    var size:int = h - margin*2;
    var x0:int = margin;
    var x1:int = w - margin;

    graphics.clear();
    graphics.beginFill(0, 0.5);
    graphics.drawRect(0, 0, w, h);
    graphics.endFill();

    playButton.resize(size, size);
    playButton.x = x0;
    playButton.y = margin;
    x0 += playButton.width + margin;

    if (fsButton != null) {
      fsButton.resize(size, size);
      fsButton.x = x1 - fsButton.width;
      fsButton.y = margin;
      x1 = fsButton.x - margin;
    }
    
    volumeSlider.resize(size*2, size);
    volumeSlider.x = x1 - volumeSlider.width;
    volumeSlider.y = margin;
    x1 = volumeSlider.x - margin;
    
    status.resize(x1-x0, size);
    status.x = x0;
    status.y = margin;
  }

  public function update():void
  {
    if (_autohide) {
      var a:Number = (_timeout - getTimer())/fadeDuration + 1.0;
      alpha = Math.min(Math.max(a, 0.0), 1.0);
    } else {
      alpha = 1.0;
    }
    status.update();
    playButton.update();
    volumeSlider.update();
    if (fsButton != null) {
      fsButton.update();
    }
  }
}


//  VolumeSlider
//  A volume slider.  (part of ControlBar)
//
class VolumeSlider extends Slider
{
  public var muteColor:uint = 0xffff0000;

  private var _value:Number = 0;
  private var _muted:Boolean = false;
  
  protected override function onMouseDrag(e:MouseEvent):void 
  {
    var size:int = buttonSize/8;
    var w:int = (width-size*2);
    value = (e.localX-size)/w;
  }

  public function get value():Number
  {
    return _value;
  }

  public function set value(v:Number):void
  {
    v = Math.max(0, Math.min(1, v));
    if (_value != v) {
      _value = v;
      invalidate();
      dispatchEvent(new Event(CHANGED));
    }
  }

  public function get muted():Boolean
  {
    return _muted;
  }

  public function set muted(value:Boolean):void
  {
    _muted = value;
    invalidate();
  }

  public override function repaint():void
  {
    super.repaint();
    var size:int = buttonSize/4;
    var color:uint = (highlit)? hiColor : fgColor;
    var cx:int = width/2;
    var cy:int = height/2;

    graphics.lineStyle(0, color, (color>>>24)/255);
    graphics.moveTo(size, height-size);
    graphics.lineTo(width-size, size);
    graphics.lineTo(width-size, height-size);
    graphics.lineTo(size, height-size);

    var w:int = (width-size*2);
    var h:int = (height-size*2);
    graphics.beginFill(color, (color>>>24)/255);
    graphics.moveTo(size, height-size);
    graphics.lineTo(size+_value*w, height-size-_value*h);
    graphics.lineTo(size+_value*w, height-size);
    graphics.endFill();

    if (_muted) {
      graphics.lineStyle(2, muteColor, (muteColor>>>24)/255);
      graphics.moveTo(cx-size, cy-size);
      graphics.lineTo(cx+size, cy+size);
    }
  }
}


//  FullscreenButton
//  Fullscreen/Windowed toggle button. (part of ControlBar)
//
class FullscreenButton extends Button
{
  private var _toFullscreen:Boolean = false;

  public function get toFullscreen():Boolean
  {
    return _toFullscreen;
  }

  public function set toFullscreen(value:Boolean):void
  {
    _toFullscreen = value;
    invalidate();
  }

  public override function repaint():void
  {
    super.repaint();
    var size:int = buttonSize/16;
    var color:uint = (highlit)? hiColor : fgColor;
    var cx:int = width/2 + ((pressed)? 1 : 0);
    var cy:int = height/2 + ((pressed)? 1 : 0);

    if (_toFullscreen) {
      graphics.beginFill(color, (color>>>24)/255);
      graphics.drawRect(cx-size*7, cy-size*4, size*14, size*8);
      graphics.endFill();
    } else {
      graphics.lineStyle(0, color, (color>>>24)/255);
      graphics.drawRect(cx-size*7, cy-size*5, size*10, size*6);
      graphics.drawRect(cx-size*2, cy-size*1, size*9, size*7);
    }
  }
}


//  PlayPauseButton
//  Play/pause toggle button. (part of ControlBar)
//
class PlayPauseButton extends Button
{
  private var _toPlay:Boolean = false;

  public function get toPlay():Boolean
  {
    return _toPlay;
  }

  public function set toPlay(value:Boolean):void
  {
    _toPlay = value;
    invalidate();
  }

  public override function repaint():void
  {
    super.repaint();
    var size:int = buttonSize/16;
    var color:uint = (highlit)? hiColor : fgColor;
    var cx:int = width/2 + ((pressed)? 1 : 0);
    var cy:int = height/2 + ((pressed)? 1 : 0);

    if (_toPlay) {
      graphics.beginFill(color, (color>>>24)/255);
      graphics.moveTo(cx-size*4, cy-size*4);
      graphics.lineTo(cx-size*4, cy+size*4);
      graphics.lineTo(cx+size*4, cy);
      graphics.endFill();
    } else {
      graphics.beginFill(color, (color>>>24)/255);
      graphics.drawRect(cx-size*3, cy-size*4, size*2, size*8);
      graphics.drawRect(cx+size*1, cy-size*4, size*2, size*8);
      graphics.endFill();
    }
  }
}


//  StatusDisplay
//  Shows a text status. (part of ControlBar)
//
class StatusDisplay extends Control
{
  private var _text:TextField;

  public function StatusDisplay()
  {
    _text = new TextField();
    _text.selectable = false;
    addChild(_text);
  }

  public function get text():String
  {
    return _text.text;
  }
  public function set text(value:String):void
  {
    _text.text = value;
  }

  public override function resize(w:int, h:int):void
  {
    super.resize(w, h);
    _text.width = w;
    _text.height = h;
  }

  public override function repaint():void
  {
    super.repaint();
    var color:uint = (highlit)? hiColor : fgColor;
    _text.textColor = color;
  }
}


//  VideoOverlay
//  A transparent button shown over the video.
//
class VideoOverlay extends Sprite
{
  public var buttonSize:int = 100;
  public var fadeDuration:int = 2000;
  public var buttonBgColor:uint = 0x448888ff;
  public var buttonFgColor:uint = 0xcc888888;

  private var _size:int;
  private var _width:int;
  private var _height:int;
  private var _playing:Boolean;
  private var _timeout:int;

  public function VideoOverlay()
  {
    _timeout = -fadeDuration;
    alpha = 0;
  }

  public function resize(w:int, h:int):void
  {
    _width = w;
    _height = h;
    repaint();
  }
  
  public function show(playing:Boolean):void
  {
    _playing = playing;
    _timeout = getTimer();
    repaint();
  }

  public function repaint():void
  {
    graphics.clear();
    graphics.beginFill(0, 0);
    graphics.drawRect(0, 0, _width, _height);
    graphics.endFill();

    var size:int = buttonSize/16;
    var cx:int = width/2;
    var cy:int = height/2;

    graphics.beginFill(buttonBgColor, (buttonBgColor>>>24)/255);
    graphics.drawRect(cx-buttonSize/2, cy-buttonSize/2, buttonSize, buttonSize);
    graphics.endFill();
    if (_playing) {
      graphics.beginFill(buttonFgColor, (buttonFgColor>>>24)/255);
      graphics.moveTo(cx-size*4, cy-size*4);
      graphics.lineTo(cx-size*4, cy+size*4);
      graphics.lineTo(cx+size*4, cy);
      graphics.endFill();
    } else {
      graphics.beginFill(buttonFgColor, (buttonFgColor>>>24)/255);
      graphics.drawRect(cx-size*3, cy-size*4, size*2, size*8);
      graphics.drawRect(cx+size*1, cy-size*4, size*2, size*8);
      graphics.endFill();
    }
  }
  
  public function update():void
  {
    var a:Number = (_timeout - getTimer())/fadeDuration + 1.0;
    alpha = Math.min(Math.max(a, 0.0), 1.0);
  }
}


//  DebugDisplay
//  Text areas showing the debug info.
//
class DebugDisplay extends Sprite
{
  private var _logger:TextField;
  private var _playstat:TextField;
  private var _streaminfo:TextField;

  public function DebugDisplay()
  {
    _logger = new TextField();
    _logger.multiline = true;
    _logger.wordWrap = true;
    _logger.border = true;
    _logger.width = 400;
    _logger.height = 100;
    _logger.background = true;
    _logger.type = TextFieldType.DYNAMIC;
    addChild(_logger);

    _playstat = new TextField();
    _playstat.multiline = true;
    _playstat.width = 200;
    _playstat.height = 100;
    _playstat.textColor = 0xffffff;
    _playstat.type = TextFieldType.DYNAMIC;
    addChild(_playstat);

    _streaminfo = new TextField();
    _streaminfo.multiline = true;
    _streaminfo.width = 200;
    _streaminfo.height = 200;
    _streaminfo.textColor = 0xffff00;
    _streaminfo.type = TextFieldType.DYNAMIC;
    addChild(_streaminfo);
  }

  public function writeLine(x:String):void
  {
    _logger.appendText(x+"\n");
    _logger.scrollV = _logger.maxScrollV;
  }

  public function resize(w:int, h:int):void
  {
    _playstat.x = w - _playstat.width;
    _playstat.y = h - _playstat.height;
    _streaminfo.x = 0;
    _streaminfo.y = h - _streaminfo.height;
  }
  
  public function update(stream:NetStream):void
  {
    if (!visible) return;

    var text:String;
    text = ("time: "+stream.time+"\n"+
	    "bufferLength: "+stream.bufferLength+"\n"+
	    "backBufferLength: "+stream.backBufferLength+"\n"+
	    "currentFPS: "+Math.floor(stream.currentFPS)+"\n"+
	    "liveDelay: "+stream.liveDelay+"\n");
    _playstat.text = text;

    var info:NetStreamInfo = stream.info;
    text = ("isLive: "+info.isLive+"\n"+
	    "byteCount: "+info.byteCount+"\n"+
	    "audioBufferLength: "+info.audioBufferLength+"\n"+
	    "videoBufferLength: "+info.videoBufferLength+"\n"+
		"currentBytesPerSecond: "+Math.floor(info.currentBytesPerSecond)+"\n"+
	    "maxBytesPerSecond: "+Math.floor(info.maxBytesPerSecond)+"\n"+
	    "audioBytesPerSecond: "+Math.floor(info.audioBytesPerSecond)+"\n"+
	    "videoBytesPerSecond: "+Math.floor(info.videoBytesPerSecond)+"\n"+
	    "playbackBytesPerSecond: "+Math.floor(info.playbackBytesPerSecond)+"\n"+
	    "droppedFrames: "+info.droppedFrames+"\n");
    _streaminfo.text = text;
  }
}
