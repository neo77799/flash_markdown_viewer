// ==================== Flash MX (AS1) Markdown viewer with scrolling & images ====================
// - URL欄に http/https の絶対URLを入れて Load
// - 同期: .md/.txt を取得 → 生テキスト表示 → 箱レイアウト描画（見出し/段落/箇条書き/引用/コード/画像）
// - 画像: ![alt](url) を検出して読み込み、横幅に合わせて自動縮小（最大高さ 360px / 拡大なし）
// - 引用: 連続する '>' 行を1つの枠にまとめ、インデントで右に寄せる
// - スクロール: ドラッグ / トラッククリック / （対応環境なら）マウスホイール
// ================================================================================================

System.useCodepage = false;                 // UTF-8 想定
var FONT_FACE  = "MS UI Gothic";            // Ruffleなら "Noto Sans JP"
var DEFAULT_URL = "https://hackmd.io/K8krp0A0QqGS0ECO4URDsg.md"; // 空欄時のフォールバック

// ------------ depth manager ------------
var __d = 1; function nextDepth(){ var d=__d; __d++; return d; }

// ------------ simple TextField factory ------------
function mkTF(name, x, y, w, h, multiline, asInput){
  _root.createTextField(name, nextDepth(), x, y, w, h);
  var tf = _root[name];
  tf.type = asInput ? "input" : "dynamic";
  tf.border = true; tf.background = true; tf.backgroundColor = 0xFFFFFF;
  tf.textColor = 0x000000; tf.selectable = !asInput;
  tf.multiline = !!multiline; tf.wordWrap = !!multiline;
  tf.embedFonts = false;
  var fmt = new TextFormat(); fmt.font = FONT_FACE; fmt.size = asInput?14:12;
  tf.setNewTextFormat(fmt); tf.defaultTextFormat = fmt;
  return tf;
}

// ------------ UI（url / load が無ければ自動生成） ------------
var haveUrl = (typeof _root.url != "undefined");
var haveBtn = (typeof _root.load != "undefined");

if (!haveUrl){
  _root.url = mkTF("url", 10, 10, 900, 26, false, true);
  url.text = DEFAULT_URL;
}else{
  var f0 = new TextFormat(); f0.font = FONT_FACE; f0.size = 14; f0.color = 0x000000;
  url.type = "input"; url.embedFonts = false; url.border = true; url.background = true;
  url.setNewTextFormat(f0); url.setTextFormat(f0);
  if (!url.text || url.text=="") url.text = DEFAULT_URL;
}

if (!haveBtn){
  _root.createEmptyMovieClip("load", nextDepth());
  load._x = 920; load._y = 10;
  with (load){ beginFill(0xE5A500,100); lineStyle(1,0x333333);
    moveTo(0,0); lineTo(120,0); lineTo(120,26); lineTo(0,26); lineTo(0,0); endFill(); }
  var lbl = mkTF("btnLabel", 920, 10, 120, 26, false, false);
  lbl.text = "Load"; lbl.selectable = false;
}

var tfStatus  = mkTF("txtStatus", 10, 42, 500, 18, false, false); tfStatus.text = "";
var tfPreview = mkTF("txtPreview", 10, 64, 1030, 480, true, false); // raw text area（マスク領域と同じサイズ）
tfPreview.html = false;
var tfLog     = mkTF("txtLog", 10, 550, 1030, 90, true, false); tfLog.text = "[log]\n";

// ------------ utils ------------
function log(s){ var t="["+getTimer()+"] "+s; trace(t); tfStatus.text=s; tfLog.text+=t+"\n"; tfLog.scroll=tfLog.maxscroll; }
function trim(s){var i=0,j=s.length-1;while(i<=j&&(s.charAt(i)==" "||s.charAt(i)=="\t"))i++;while(j>=i&&(s.charAt(j)==" "||s.charAt(j)=="\t"))j--;return s.substring(i,j+1);}
function isHttp(u){ return (u.substr(0,7)=="http://" || u.substr(0,8)=="https://"); }
function cacheBust(u){ if(!u||u.length==0) return u; return u+((u.indexOf("?")>=0)?"&":"?")+"t="+getTimer(); }

var CURRENT_MD_BASE = ""; // 画像相対URLを解決するためのMDファイルのベースURL
function resolveRes(u){
  u = trim(u);
  if (isHttp(u)) return u;        // 絶対URL
  if (u.substr(0,2)=="//") return "https:"+u; // protocol-relative
  return CURRENT_MD_BASE + u;     // 相対URLはMDの場所基準
}

// ==================== Markdown block renderer (+ viewport & scrollbar & images) ====================
var MD_STYLE = {
  fontBody: FONT_FACE,
  fontMono: "Courier New",
  fontHead: FONT_FACE,
  colorText: 0x000000,
  colorBorder: 0xCCCCCC,
  colorRule: 0xDDDDDD,
  colorQuoteBg: 0xFAFAFA,
  colorCodeBg: 0xF5F5F5,
  padBox: 6,
  marginY: 8,

  // ↓追加：見出しの下線スタイル
  colorHeadRule: 0xE6E6E6,  // 線色
  h1RuleThick: 2,           // H1の太さ
  h2RuleThick: 1,           // H2の太さ
  h3RuleThick: 1,           // H3の太さ
  h1RuleGapTop: 8,          // 見出し→線の間
  h1RuleGapBottom: 10,      // 線→本文の間
  h2RuleGapTop: 6,
  h2RuleGapBottom: 8,
  h3RuleGapTop: 6,
  h3RuleGapBottom: 6,
  h3RuleWidthRatio: 1.0     // H3の線の長さ（1.0=全幅, 0.5=半分だけ）
};

var __md_rootDepth = 5000; // viewport container depth (fixed)
var __scrollDepth  = 6000; // scrollbar depth
var __lastView = {x:0,y:0,w:0,h:0};

function mdTrim(s){var i=0,j=s.length-1;while(i<=j&&(s.charAt(i)==" "||s.charAt(i)=="\t"))i++;while(j>=i&&(s.charAt(j)==" "||s.charAt(j)=="\t"))j--;return s.substring(i,j+1);}
function mdIsRule(t){var c=null,cnt=0;for(var i=0;i<t.length;i++){var ch=t.charAt(i);if(ch==" "||ch=="\t")continue;if(c==null){if(ch=="-"||ch=="*"){c=ch;cnt++;}else{return false;}}else{if(ch==c)cnt++;else return false;}}return(cnt>=3);}

// ---- 引用ヘルパ（追加） ----
function mdLeadSpaces(s){
  var i=0;
  while (i<s.length){
    var ch = s.charAt(i);
    if (ch==" ") i++;
    else if (ch=="\t") i += 2; // タブは2相当
    else break;
  }
  return i;
}
function mdIndentLevel(s){
  var sp = mdLeadSpaces(s);
  return Math.floor(sp/2); // 2スペースで1レベル
}
function mdIsQuoteLine(s){
  var i = mdLeadSpaces(s);
  return (s.charAt(i)==">");
}
function mdStripQuoteMarker(s){
  var i = mdLeadSpaces(s);
  if (s.charAt(i)==">") i++;
  return mdTrim(s.substr(i));
}

// --- viewport helpers ---
function killOldViewport(){
  if (_root.mdView){ _root.mdView.removeMovieClip(); }
  if (_root.mdMask){ _root.mdMask.removeMovieClip(); }
  if (_root.mdScroll){ _root.mdScroll.removeMovieClip(); }
}

function createViewport(x, y, w, h){
  killOldViewport();
  _root.createEmptyMovieClip("mdView", __md_rootDepth);
  _root.createEmptyMovieClip("mdMask", __md_rootDepth+1);
  var v = _root.mdView, m = _root.mdMask;
  v._x = x; v._y = y;
  m._x = x; m._y = y;
  m.beginFill(0x000000, 100);
  m.moveTo(0,0); m.lineTo(w,0); m.lineTo(w,h); m.lineTo(0,h); m.lineTo(0,0);
  m.endFill();
  v.setMask(m);
  v.createEmptyMovieClip("content", 1);
  return v;
}

function refreshScrollbar(){
  if (!_root.mdView) return;
  var v = _root.mdView;
  installScrollbar(__lastView.x, __lastView.y, __lastView.w, __lastView.h, v.content._height);
}

// --- installScrollbar（グローバル座標→ローカル変換でドラッグ更新） ---
function installScrollbar(viewX, viewY, viewW, viewH, contentH){
  if (_root.mdScroll) _root.mdScroll.removeMovieClip();
  _root.createEmptyMovieClip("mdScroll", __scrollDepth);
  var sc = _root.mdScroll;
  sc._x = viewX + viewW + 6;
  sc._y = viewY;

  var trackW = 12;
  var trackH = viewH;

  // track
  sc.createEmptyMovieClip("track", 1);
  with (sc.track){
    lineStyle(1, 0xBBBBBB, 100); beginFill(0xF2F2F2, 100);
    moveTo(0,0); lineTo(trackW,0); lineTo(trackW,trackH); lineTo(0,trackH); lineTo(0,0);
    endFill();
    useHandCursor = false;
  }

  // thumb
  var thMin = 20;
  var thH = (contentH <= viewH) ? trackH : Math.max(thMin, Math.floor(viewH*viewH/contentH));
  sc.createEmptyMovieClip("thumb", 2);
  with (sc.thumb){
    lineStyle(1, 0x888888, 100); beginFill(0xCFCFCF, 100);
    moveTo(1,1); lineTo(trackW-1,1); lineTo(trackW-1,thH-1); lineTo(1,thH-1); lineTo(1,1);
    endFill();
    _x = 0; _y = 0; useHandCursor = false;
  }

  var clamp = function(v,a,b){ if(v<a) return a; if(v>b) return b; return v; };
  var contentClip = _root.mdView.content;
  var denom = (trackH - thH); if (denom < 0) denom = 0;

  var localMouseY = function(){
    var p = {x:_root._xmouse, y:_root._ymouse};
    sc.globalToLocal(p);
    return p.y;
  };

  var toR   = function(y){ if (denom<=0) return 0; return clamp(y/denom, 0, 1); };
  var fromR = function(r){ return clamp(r,0,1) * denom; };

  var applyR = function(r){
    r = clamp(r,0,1);
    sc.thumb._y = Math.round(fromR(r));
    var maxScroll = Math.max(0, contentH - viewH);
    contentClip._y = -Math.round(maxScroll * r);
  };

  // drag
  var dragging = false;
  var dragOff  = 0;
  sc.thumb.onPress = function(){ dragging = true; dragOff = localMouseY() - sc.thumb._y; };
  sc.thumb.onRelease = sc.thumb.onReleaseOutside = function(){ dragging = false; };

  // track click
  sc.track.onPress = function(){
    var newY = clamp(localMouseY() - thH*0.5, 0, denom);
    applyR(toR(newY));
  };

  // wheel
  var wheel = {};
  wheel.onMouseWheel = function(delta){
    if (denom <= 0) return;
    var r = toR(sc.thumb._y) - delta * (viewH / contentH) * 0.15;
    applyR(r);
  };
  Mouse.addListener(wheel);

  // update during drag
  sc.onEnterFrame = function(){
    if (dragging){
      var newY = clamp(localMouseY() - dragOff, 0, denom);
      applyR(toR(newY));
      updateAfterEvent();
    }
  };

  applyR(0);
  sc._visible = (contentH > viewH);
  if (contentH <= viewH) contentClip._y = 0;
}

// --- renderer entry ---
// md: text, (x,y): viewport origin, w: viewport width, h: viewport height
function renderMarkdownBlocks(md, x, y, w, h){
  __lastView = {x:x,y:y,w:w,h:h};
  var view = createViewport(x, y, w, h);
  var panel = view.content;

  var curY = 0;
  var nDepth = 1; function nd(){ return nDepth++; }

  function tfMake(mc, name, X, Y, W, txt, font, size, bold, italic){
    var id = nd();
    mc.createTextField(name, id, X, Y, W, 20);
    var tf = mc[name];
    tf.type = "dynamic"; tf.selectable = true;
    tf.border = false; tf.background = false; tf.embedFonts = false;
    tf.multiline = true; tf.wordWrap = true;
    var fmt = new TextFormat();
    fmt.font = font; fmt.size = size; fmt.bold = !!bold; fmt.italic = !!italic; fmt.color = MD_STYLE.colorText;
    tf.setNewTextFormat(fmt); tf.defaultTextFormat = fmt;
    tf.text = txt;
    tf._height = tf.textHeight + 4;
    return tf;
  }

  function addSpacer(hh){ curY += hh; }

  function addRule(){
    var id = nd(), nm = "hr"+id;
    panel.createEmptyMovieClip(nm, id);
    var hr = panel[nm]; hr._x = 0; hr._y = curY + 6;
    hr.lineStyle(1, MD_STYLE.colorRule, 100);
    hr.moveTo(0,0); hr.lineTo(w,0);
    curY += 14;
  }

  function addHeading(txt, level){
    // フォントサイズ
    var size = (level==1)?24:(level==2)?20:(level==3)?18:(level==4)?16:(level==5)?14:13;
  
    // 見出しテキスト
    var tfh = tfMake(panel, "h"+nd(), 0, curY, w, txt, MD_STYLE.fontHead, size, true, false);
    curY += tfh._height;  // テキスト分の高さを進める
  
    // ---- 下線（レベル別スタイル） ----
    var thick, gapTop, gapBottom, lineW;
    if (level==1){
      thick = MD_STYLE.h1RuleThick; gapTop = MD_STYLE.h1RuleGapTop; gapBottom = MD_STYLE.h1RuleGapBottom; lineW = w;
    }else if (level==2){
      thick = MD_STYLE.h2RuleThick; gapTop = MD_STYLE.h2RuleGapTop; gapBottom = MD_STYLE.h2RuleGapBottom; lineW = w;
    }else{ // level >= 3
      thick = MD_STYLE.h3RuleThick; gapTop = MD_STYLE.h3RuleGapTop; gapBottom = MD_STYLE.h3RuleGapBottom;
      lineW = Math.round(w * MD_STYLE.h3RuleWidthRatio);  // 例: 1.0なら全幅
    }
  
    // 見出し下の余白 → 線
    var id = nd(), nm = "hru"+id;
    panel.createEmptyMovieClip(nm, id);
    var ru = panel[nm];
    ru._x = 0;
    ru._y = curY + gapTop;
    ru.lineStyle(thick, MD_STYLE.colorHeadRule, 100);
    ru.moveTo(0, 0);
    ru.lineTo(lineW, 0);
  
    // 線の下の余白を加算
    curY += gapTop + gapBottom;
  }


  function addParagraph(txt){
    var tfp = tfMake(panel, "p"+nd(), 0, curY, w, txt, MD_STYLE.fontBody, 12, false, false);
    curY += tfp._height + MD_STYLE.marginY;
  }

  // 引用（インデント対応・連結済テキスト）
  function addQuote(txt, indent){
    var pad = MD_STYLE.padBox;
    var leftShift = indent * 16;        // インデント幅
    var widthQ = w - leftShift;         // ボックス幅
    var id = nd(), nm = "q"+id;
    panel.createEmptyMovieClip(nm, id);
    var box = panel[nm];

    var innerW = widthQ - pad*2 - 4;
    var t = tfMake(box, "t", pad+8, pad, innerW, txt, MD_STYLE.fontBody, 12, false, false);
    var boxH = t._height + pad*2;

    box.beginFill(MD_STYLE.colorQuoteBg, 100);
    box.lineStyle(1, MD_STYLE.colorBorder, 100);
    box.moveTo(0,0); box.lineTo(widthQ,0); box.lineTo(widthQ, boxH); box.lineTo(0, boxH); box.lineTo(0,0); box.endFill();
    box.beginFill(0xBBBBBB, 100);
    box.moveTo(2,0); box.lineTo(6,0); box.lineTo(6, boxH); box.lineTo(2, boxH); box.lineTo(2,0); box.endFill();

    box._x = leftShift;
    box._y = curY;
    curY += boxH + MD_STYLE.marginY;
  }

  function addCode(txt){
    var id = nd(), nm = "c"+id;
    panel.createEmptyMovieClip(nm, id);
    var box = panel[nm]; var pad = MD_STYLE.padBox;
    var innerW = w - pad*2;
    var t = tfMake(box, "t"+id, pad, pad, innerW, txt, MD_STYLE.fontMono, 12, false, false);
    var boxH = t._height + pad*2;
    box.beginFill(MD_STYLE.colorCodeBg, 100);
    box.lineStyle(1, MD_STYLE.colorBorder, 100);
    box.moveTo(0,0); box.lineTo(w,0); box.lineTo(w, boxH); box.lineTo(0, boxH); box.lineTo(0,0); box.endFill();
    box._y = curY;
    curY += boxH + MD_STYLE.marginY;
  }

  function addBullet(txt, indent){
    var id = nd(), nm = "li"+id;
    panel.createEmptyMovieClip(nm, id);
    var blk = panel[nm]; var leftPad = 14 + indent*16;
    var t = tfMake(blk, "t"+id, leftPad, 0, w - leftPad, txt, MD_STYLE.fontBody, 12, false, false);
    var h = t._height;
    blk.beginFill(MD_STYLE.colorText, 100);
    var yb = Math.max(4, (h-4)/2);
    blk.moveTo(leftPad-10, yb); blk.lineTo(leftPad-6, yb); blk.lineTo(leftPad-6, yb+4); blk.lineTo(leftPad-10, yb+4); blk.lineTo(leftPad-10, yb);
    blk.endFill();
    blk._y = curY; curY += h + 4;
  }

  function addOrdered(prefix, txt, indent){
    var id = nd(), nm = "ol"+id;
    panel.createEmptyMovieClip(nm, id);
    var blk = panel[nm]; var leftPad = 8 + indent*16;
    var p = tfMake(blk, "p"+id, leftPad, 0, 22, prefix + ".", MD_STYLE.fontBody, 12, true, false);
    var t = tfMake(blk, "t"+id, leftPad + 22, 0, w - (leftPad + 22), txt, MD_STYLE.fontBody, 12, false, false);
    var h = Math.max(p._height, t._height);
    p._height = h; t._height = h;
    blk._y = curY; curY += h + 4;
  }

  // 画像（loadMovie + polling + ログ）
  function addImage(urlStr, alt){
    var id = nd(), nm = "img"+id;
    panel.createEmptyMovieClip(nm, id);
    var box = panel[nm];
    var pad = MD_STYLE.padBox;
    var innerW = w - pad*2;

    box.createEmptyMovieClip("pic", 1);
    box.pic._x = pad; box.pic._y = pad;

    var cap = tfMake(box, "cap"+id, pad, pad, innerW,
                     (alt && alt.length ? alt : "loading image..."),
                     MD_STYLE.fontBody, 12, false, false);
    cap.textColor = 0x666666;
    cap._y = pad + 140 + 4;

    var boxH = pad + 140 + 4 + cap._height + pad;
    box.beginFill(0xFFFFFF, 100);
    box.lineStyle(1, MD_STYLE.colorBorder, 100);
    box.moveTo(0,0); box.lineTo(w,0); box.lineTo(w, boxH); box.lineTo(0, boxH); box.lineTo(0,0); box.endFill();
    box._y = curY; curY += boxH + MD_STYLE.marginY;

    var resolved = cacheBust(resolveRes(urlStr));
    log("img: parse  " + urlStr);
    log("img: load   " + resolved);

    box.pic.loadMovie(resolved);

    var t0 = getTimer();
    var TIMEOUT = 12000;
    var loggedStart = false;

    box.onEnterFrame = function(){
      var mc = this.pic;
      var w0 = mc._width;
      var h0 = mc._height;

      if (!loggedStart && (mc.getBytesTotal() > 0)){
        loggedStart = true;
        log("img: start  bt=" + mc.getBytesTotal());
      }

      if (w0 > 0 && h0 > 0){
        var ow = w0, oh = h0;
        var rx = innerW / ow;
        var ry = 360 / oh;
        var r  = rx; if (ry < r) r = ry; if (r > 1) r = 1;
        mc._xscale = r * 100;
        mc._yscale = r * 100;

        var sw = Math.round(mc._width);
        var sh = Math.round(mc._height);

        cap._y = pad + sh + 4;
        var newH = pad + sh + 4 + cap._height + pad;
        box.clear();
        box.beginFill(0xFFFFFF, 100);
        box.lineStyle(1, MD_STYLE.colorBorder, 100);
        box.moveTo(0,0); box.lineTo(w,0); box.lineTo(w, newH); box.lineTo(0, newH); box.lineTo(0,0); box.endFill();

        log("img: ok     " + Math.round(ow) + "x" + Math.round(oh) + " -> " + sw + "x" + sh);
        refreshScrollbar();
        delete this.onEnterFrame;
        return;
      }

      if (getTimer() - t0 > TIMEOUT){
        cap.text = "image load timeout";
        log("img: timeout " + resolved +
            " bl/bt=" + mc.getBytesLoaded() + "/" + mc.getBytesTotal());
        refreshScrollbar();
        delete this.onEnterFrame;
      }
    };
  }

  // ---- parse & layout ----
  md = md.split("\r\n").join("\n"); md = md.split("\r").join("\n");
  var L = md.split("\n"); var inCode=false, buf="", codeBuf="";
  for (var i=0;i<L.length;i++){
    var line=L[i]; var t=mdTrim(line);

    if (t.substr(0,3)=="```"){ if(!inCode){inCode=true; codeBuf="";} else { addCode(codeBuf); inCode=false; } continue; }
    if (inCode){ codeBuf += line + "\n"; continue; }

    // image block: ![alt](url)
    if (t.substr(0,2)=="!["){
      var rb = t.indexOf("]",2);
      if (rb>2 && rb+1<t.length && t.charAt(rb+1)=="("){
        var rp = t.indexOf(")", rb+2);
        if (rp>rb){
          var alt = t.substring(2, rb);
          var u   = mdTrim(t.substring(rb+2, rp));
          log("img: parse  " + u);
          addImage(u, alt);
          continue;
        }
      }
    }

    // ====== 引用：連続する '>' を一つにまとめる + インデント反映 ======
    if (mdIsQuoteLine(line)){
      var ind = mdIndentLevel(line);
      var qbuf = mdStripQuoteMarker(line);
      var j = i + 1;
      while (j < L.length){
        var ln2 = L[j];
        if (!mdIsQuoteLine(ln2)) break;
        if (mdIndentLevel(ln2) != ind) break; // インデント違いは別枠
        var part = mdStripQuoteMarker(ln2);
        qbuf += (part.length ? ("\n"+part) : "\n");
        j++;
      }
      addQuote(qbuf, ind);
      i = j - 1;
      continue;
    }

    if (t.length==0){ if(buf.length){ addParagraph(buf); buf=""; } addSpacer(2); continue; }

    var h2=0; while(h2<t.length && t.charAt(h2)=="#") h2++;
    if (h2>0 && (t.charAt(h2)==" " || h2==t.length)){ addHeading(mdTrim(t.substr(h2)), Math.min(6,h2)); continue; }

    if (mdIsRule(t)){ addRule(); continue; }
    if ((t.charAt(0)=="-"||t.charAt(0)=="*"||t.charAt(0)=="+") && t.charAt(1)==" "){ addBullet(t.substr(2), 0); continue; }

    var j2=0; while(j2<t.length && t.charAt(j2)>="0" && t.charAt(j2)<="9") j2++;
    if (j2>0 && t.charAt(j2)=="." && t.charAt(j2+1)==" "){ addOrdered(t.substr(0,j2), t.substr(j2+2), 0); continue; }

    if (buf.length) buf += " " + t; else buf = t;
  }
  if (inCode) addCode(codeBuf);
  if (buf.length) addParagraph(buf);

  // content height & scrollbar
  installScrollbar(x, y, w, h, panel._height);
}

// ==================== loader ====================
var lv = new LoadVars();
lv.onData = function(raw){
  if (raw == undefined){ log("load error or CORS blocked."); return; }
  log("loaded " + raw.length + " bytes.");

  // raw text 表示（デバッグ用）
  tfPreview.html = false; tfPreview.text = raw;

  // 箱レイアウト + スクロール
  renderMarkdownBlocks(raw, tfPreview._x, tfPreview._y, tfPreview._width, tfPreview._height);

  // 生テキスト欄は非表示に
  tfPreview._visible = false;
};

function doLoad(u_){
  var u = (typeof u_=="string") ? trim(u_) :
          ((typeof url!="undefined" && typeof url.text!="undefined") ? trim(url.text) : "");
  if (!u.length) u = DEFAULT_URL;

  if (!isHttp(u)){ log("Please enter an absolute http(s) URL. got: " + u); return; }

  var k = u.lastIndexOf("/"); CURRENT_MD_BASE = (k>=0)? u.substring(0,k+1) : "";

  log("loading: " + u);
  lv.load(cacheBust(u));
}
load.onRelease = function(){ doLoad(url.text); };

// 初期文言
tfPreview.text = "Enter a URL (e.g. https://.../test.md) and press Load.\nRaw text will be shown here.";
