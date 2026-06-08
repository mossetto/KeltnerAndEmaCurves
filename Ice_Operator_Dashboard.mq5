//+------------------------------------------------------------------+
//| ice_Operator_Dashboard                                           |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

input group "Dashboard"
input color  InpBtnColor     = clrDarkSlateGray;
input color  InpTextColor    = clrWhite;
input color  InpActiveColor  = clrDodgerBlue;
input int    InpBtnWidth     = 85;
input int    InpChkSize      = 20;
input int    InpRowHeight    = 20;
input int    InpXOffset      = 3;
input int    InpYStart       = 28;
input int    InpSpacing      = 1;
input int    InpFontSize     = 9;

string _PFX   = "ICE_D_";
string _FILE  = "ice_dashboard.csv";

struct SState { string s; bool w, r, g; };
SState _st[];
int _filter = -1;
bool _collapsed = false;

//+------------------------------------------------------------------+
int OnInit() {
   Load();
   Draw();
   ChartRedraw();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int) { Clean(); }

int OnCalculate(const int, const int, const int, const double &[]) { return 0; }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &, const double &, const string &sp) {
   if(id == CHARTEVENT_OBJECT_CLICK) {
      string obj = sp;
      if(StringFind(obj, _PFX) != 0) return;
      string tag = StringSubstr(obj, StringLen(_PFX));

      if(StringFind(tag, "F_") == 0) {
         string f = StringSubstr(tag, 2);
         if(f == "A") _filter = -1;
         else if(f == "W") { _filter = 0; PrintList(0); }
         else if(f == "R") { _filter = 1; PrintList(1); }
         else if(f == "G") { _filter = 2; PrintList(2); }
         else if(f == "T") { _collapsed = !_collapsed; Save(); }
         Clean(); Draw(); ChartRedraw();
         return;
      }

      if(StringFind(tag, "B_") == 0) {
         string sym = StringSubstr(tag, 2);
         if(sym != _Symbol) ChartSetSymbolPeriod(0, sym, PERIOD_CURRENT);
         return;
      }

      if(StringFind(tag, "C_") == 0) {
         string chk = StringSubstr(tag, 2, 1);
         string sym = StringSubstr(tag, 4);
         for(int i = 0; i < ArraySize(_st); i++) {
            if(_st[i].s == sym) {
               if(chk == "W") _st[i].w = !_st[i].w;
               if(chk == "R") _st[i].r = !_st[i].r;
               if(chk == "G") _st[i].g = !_st[i].g;
               break;
            }
         }
         Save(); Clean(); Draw(); ChartRedraw();
         return;
      }
   }

   if(id == CHARTEVENT_CHART_CHANGE) {
      Load(); Clean(); Draw(); ChartRedraw();
   }
}

//+------------------------------------------------------------------+
void PrintList(int colorIdx) {
   string out = "";
   for(int i = 0; i < ArraySize(_st); i++) {
      bool match = (colorIdx == 0 && _st[i].w) || (colorIdx == 1 && _st[i].r) || (colorIdx == 2 && _st[i].g);
      if(match) {
         if(out != "") out += ",";
         out += _st[i].s;
      }
   }
   if(out != "") Print(out);
}

void Draw() {
   DrawFilters();
   if(!_collapsed) DrawSymbols();
}

//+------------------------------------------------------------------+
void DrawFilters() {
   string lbl[5] = {"All", "W", "R", "G", _collapsed ? "\x25B2" : "\x25BC"};
   string tag[5] = {"A", "W", "R", "G", "T"};
   color  bg[5]  = {clrRoyalBlue, clrWhite, clrRed, clrLimeGreen, InpBtnColor};
   color  fg[5]  = {clrWhite, clrBlack, clrWhite, clrWhite, InpTextColor};
   int    wf[5]  = {38, 24, 24, 24, 22};

   int x = InpXOffset;
   for(int i = 0; i < 5; i++) {
      bool active = (i==0&&_filter==-1)||(i==1&&_filter==0)||(i==2&&_filter==1)||(i==3&&_filter==2)||(i==4);
      string nm = _PFX + "F_" + tag[i];
      ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 2);
      ObjectSetInteger(0, nm, OBJPROP_XSIZE, wf[i]);
      ObjectSetInteger(0, nm, OBJPROP_YSIZE, InpRowHeight);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetString(0, nm, OBJPROP_TEXT, lbl[i]);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, active ? fg[i] : InpTextColor);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, active ? bg[i] : InpBtnColor);
      ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, active ? clrWhite : clrGray);
      ObjectSetInteger(0, nm, OBJPROP_BACK, false);
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      x += wf[i] + InpSpacing;
   }
}

//+------------------------------------------------------------------+
void DrawSymbols() {
   int total = SymbolsTotal(true);
   int idx = 0;

   for(int i = 0; i < total; i++) {
      string sym = SymbolName(i, true);
      if(sym == "") continue;

      SState st = GetState(sym);

      bool visible = true;
      if(_filter == 0 && !st.w) visible = false;
      if(_filter == 1 && !st.r) visible = false;
      if(_filter == 2 && !st.g) visible = false;

      if(!visible) continue;

      int y = InpYStart + idx * (InpRowHeight + InpSpacing);
      int bx = InpXOffset;

      string bnm = _PFX + "B_" + sym;
      ObjectCreate(0, bnm, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, bnm, OBJPROP_XDISTANCE, bx);
      ObjectSetInteger(0, bnm, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, bnm, OBJPROP_XSIZE, InpBtnWidth);
      ObjectSetInteger(0, bnm, OBJPROP_YSIZE, InpRowHeight);
      ObjectSetInteger(0, bnm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bnm, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetString(0, bnm, OBJPROP_TEXT, sym);
      ObjectSetInteger(0, bnm, OBJPROP_COLOR, InpTextColor);
      ObjectSetInteger(0, bnm, OBJPROP_BGCOLOR, (sym == _Symbol) ? InpActiveColor : InpBtnColor);
      ObjectSetInteger(0, bnm, OBJPROP_BORDER_COLOR, clrGray);
      ObjectSetInteger(0, bnm, OBJPROP_BACK, false);
      ObjectSetInteger(0, bnm, OBJPROP_STATE, false);
      ObjectSetInteger(0, bnm, OBJPROP_SELECTABLE, false);

      int cx = bx + InpBtnWidth + InpSpacing + 1;
      int sz = InpChkSize;

      DrawChk(_PFX + "C_W_" + sym, cx, y, sz, InpRowHeight, st.w, clrWhite, clrBlack, "W");
      DrawChk(_PFX + "C_R_" + sym, cx+sz+1, y, sz, InpRowHeight, st.r, clrRed, clrWhite, "R");
      DrawChk(_PFX + "C_G_" + sym, cx+(sz+1)*2, y, sz, InpRowHeight, st.g, clrLimeGreen, clrWhite, "G");

      idx++;
   }
}

//+------------------------------------------------------------------+
void DrawChk(string nm, int x, int y, int w, int h, bool chk, color c, color tc, string txt) {
   ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetString(0, nm, OBJPROP_TEXT, chk ? txt : "");
   ObjectSetInteger(0, nm, OBJPROP_COLOR, chk ? tc : clrDimGray);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, chk ? c : InpBtnColor);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, chk ? c : clrDimGray);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_STATE, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
SState GetState(string sym) {
   for(int i = 0; i < ArraySize(_st); i++) {
      if(_st[i].s == sym) return _st[i];
   }
   SState st; st.s = sym; st.w = false; st.r = false; st.g = false;
   return st;
}

//+------------------------------------------------------------------+
void Clean() {
   int t = ObjectsTotal(0);
   for(int i = t - 1; i >= 0; i--) {
      string n = ObjectName(0, i);
      if(StringFind(n, _PFX) == 0) ObjectDelete(0, n);
   }
}

//+------------------------------------------------------------------+
void Save() {
   int h = FileOpen(_FILE, FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
   if(h == INVALID_HANDLE) return;
   FileWrite(h, "_COLLAPSED_", (int)_collapsed);
   for(int i = 0; i < ArraySize(_st); i++) {
      FileWrite(h, _st[i].s, (int)_st[i].w, (int)_st[i].r, (int)_st[i].g);
   }
   FileClose(h);
}

//+------------------------------------------------------------------+
void Load() {
   int total = SymbolsTotal(true);
   ArrayResize(_st, total);
   for(int i = 0; i < total; i++) {
      _st[i].s = SymbolName(i, true);
      _st[i].w = false; _st[i].r = false; _st[i].g = false;
   }
   _collapsed = false;

   int h = FileOpen(_FILE, FILE_READ|FILE_CSV|FILE_ANSI, ",");
   if(h == INVALID_HANDLE) return;

   if(!FileIsEnding(h)) {
      string first = FileReadString(h);
      if(first == "_COLLAPSED_") {
         _collapsed = (int)FileReadNumber(h) != 0;
      } else {
         int w = (int)FileReadNumber(h);
         int r = (int)FileReadNumber(h);
         int g = (int)FileReadNumber(h);
         for(int i = 0; i < total; i++) {
            if(_st[i].s == first) {
               _st[i].w = (w != 0); _st[i].r = (r != 0); _st[i].g = (g != 0);
               break;
            }
         }
      }
   }

   while(!FileIsEnding(h)) {
      string sym = FileReadString(h);
      if(sym == "") continue;
      int w = (int)FileReadNumber(h);
      int r = (int)FileReadNumber(h);
      int g = (int)FileReadNumber(h);
      for(int i = 0; i < total; i++) {
         if(_st[i].s == sym) {
            _st[i].w = (w != 0); _st[i].r = (r != 0); _st[i].g = (g != 0);
            break;
         }
      }
   }
   FileClose(h);
}
//+------------------------------------------------------------------+
