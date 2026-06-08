//+------------------------------------------------------------------+
//| ChartToolPanel.mq5                                               |
//|                                                                  |
//| Boton FIX (esquina inferior derecha):                            |
//|   toggle Scale Fix — verde=activo, blanco=inactivo               |
//|   cuando activa: max=9999999999, min=0                           |
//|                                                                  |
//| Shortcuts de teclado (posicion del mouse al presionar):          |
//|   1 — flecha                                                     |
//|   2 — rectangulo                                                 |
//|   3 — linea horizontal eterna                                    |
//|   4 — linea vertical eterna                                      |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#import "user32.dll"
   void  mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, uint dwExtraInfo);
   short GetAsyncKeyState(int vKey);
#import
#define MOUSEEVENTF_LEFTDOWN 0x0002
#define MOUSEEVENTF_LEFTUP   0x0004
#define VK_E                 0x45

#define PREFIX  "CTP_"
#define BFIX    PREFIX"BTN_FIX"
#define BTRASH  PREFIX"BTN_TRASH"
#define BSCROLL PREFIX"BTN_SCROLL"
#define BSHIFT  PREFIX"BTN_SHIFT"
#define BBEGIN  PREFIX"BTN_BEGIN"

datetime g_mouseTime  = 0;
double   g_mousePrice = 0.0;
int      g_cnt        = 0;
bool     g_eHeld      = false;  // E esta siendo mantenida presionada

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "ChartToolPanel");
   ChartSetInteger(0, CHART_MOUSE_SCROLL, true);  // asegurar scroll siempre activo
   EventSetMillisecondTimer(10);  // para detectar suelta de la tecla E
   CreatePanel();
   UpdateFixButton();
   UpdateScrollButton();
   UpdateShiftButton();
   ChartRedraw();
   return INIT_SUCCEEDED;
}

void OnTimer()
{
   // Si E fue soltada, liberar el click
   if(g_eHeld && (GetAsyncKeyState(VK_E) & 0x8000) == 0)
   {
      mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
      g_eHeld = false;
   }
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_eHeld) { mouse_event(MOUSEEVENTF_LEFTUP,0,0,0,0); g_eHeld=false; }
   ChartSetInteger(0, CHART_MOUSE_SCROLL, true);  // restaurar scroll al quitar el indicador
   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw();
}

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[],  const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[],  const int &spread[])
{
   UpdateFixButton();
   return rates_total;
}

//+------------------------------------------------------------------+
int PriceScaleWidth()
{
   // Ancho de la barra de precios = diferencia entre ancho total y ancho visible del chart
   int totalW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int visibleBars = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   int barW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS) / MathMax(visibleBars, 1);
   // Estimacion directa: suele ser 60-80px; usamos diferencia real si disponible
   int scaleW = totalW - (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   // Fallback: usar margen fijo de 70px que cubre la mayoria de configuraciones
   return 70;
}

void CreatePanel()
{
   int mx = PriceScaleWidth() + 6 - 15 - 39 + 10;
   int my = 30 - 5;
   int W  = 39, H = 14, GAP = 3;
   MakeBtn(BFIX,    "FIX =8", mx, my,            W, H);
   MakeBtn(BSHIFT,  "SHF =9", mx, my+(H+GAP),   W, H);
   MakeBtn(BSCROLL, "AS  =0", mx, my+(H+GAP)*2, W, H);
   MakeBtn(BBEGIN,  "<<",     mx, my+(H+GAP)*3, W, H);
   MakeBtn(BTRASH,  "X",      mx, my+(H+GAP)*4, W, H);
}

void MakeBtn(string name, string label, int xdist, int ydist, int w, int h)
{
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,    CORNER_RIGHT_LOWER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE, xdist);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE, ydist);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,     w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,     h);
   ObjectSetString (0,name,OBJPROP_TEXT,      label);
   ObjectSetString (0,name,OBJPROP_FONT,      "Arial Bold");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,  7);
   ObjectSetInteger(0,name,OBJPROP_COLOR,     clrBlack);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,   clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR, clrGray);
   ObjectSetInteger(0,name,OBJPROP_STATE,     false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,      false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,    10);
}

//+------------------------------------------------------------------+
void ToggleAutoScroll()
{
   bool current = (bool)ChartGetInteger(0, CHART_AUTOSCROLL);
   ChartSetInteger(0, CHART_AUTOSCROLL, !current);
   UpdateScrollButton();
   ChartRedraw();
}

void UpdateShiftButton()
{
   if(ObjectFind(0,BSHIFT)<0) return;
   bool active=(bool)ChartGetInteger(0,CHART_SHIFT);
   ObjectSetInteger(0,BSHIFT,OBJPROP_BGCOLOR, active ? clrDeepSkyBlue : clrGray);
   ObjectSetInteger(0,BSHIFT,OBJPROP_COLOR,   clrWhite);
}

void UpdateScrollButton()
{
   if(ObjectFind(0,BSCROLL)<0) return;
   bool active=(bool)ChartGetInteger(0,CHART_AUTOSCROLL);
   ObjectSetInteger(0,BSCROLL,OBJPROP_BGCOLOR, active ? clrDeepSkyBlue : clrGray);
   ObjectSetInteger(0,BSCROLL,OBJPROP_COLOR,   clrWhite);
}

void UpdateFixButton()
{
   bool active=(bool)ChartGetInteger(0,CHART_SCALEFIX);
   if(ObjectFind(0,BFIX)<0) return;
   ObjectSetInteger(0,BFIX,OBJPROP_BGCOLOR, active ? clrLimeGreen : clrWhite);
   ObjectSetInteger(0,BFIX,OBJPROP_COLOR,   active ? clrWhite     : clrBlack);
}

//+------------------------------------------------------------------+
void ToggleScaleFix()
{
   bool active=(bool)ChartGetInteger(0,CHART_SCALEFIX);
   if(active)
   {
      ChartSetInteger(0,CHART_SCALEFIX,false);
   }
   else
   {
      // Calcular max/min de las velas actualmente visibles
      int firstBar = (int)ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR);
      int visiBars = (int)ChartGetInteger(0,CHART_VISIBLE_BARS);
      double hi=-DBL_MAX, lo=DBL_MAX;
      for(int i=firstBar; i<firstBar+visiBars && i>=0; i++)
      {
         double h=iHigh(_Symbol,PERIOD_CURRENT,i);
         double l=iLow (_Symbol,PERIOD_CURRENT,i);
         if(h>hi) hi=h;
         if(l<lo) lo=l;
      }
      // Centrar en el area visible y dar ±500 veces el rango visible de espacio libre
      // El chart arranca posicionado donde corresponde y hay amplio margen para moverse
      double margin = (hi-lo)*0.03;
      double mid    = (hi+lo)/2.0;
      double swing  = (hi-lo+margin*2.0)*500.0;   // 500x el rango visible en cada direccion
      double fixMax = mid+swing;
      double fixMin = MathMax(0.0, mid-swing);
      ChartSetInteger(0,CHART_SCALEFIX,true);
      ChartSetDouble (0,CHART_FIXED_MAX,fixMax);
      ChartSetDouble (0,CHART_FIXED_MIN,fixMin);
   }
   ChartRedraw();
   UpdateFixButton();
}

//+------------------------------------------------------------------+
string UniqueName(string type)
{
   return PREFIX+type+"_"+(string)(g_cnt++);
}

void PlaceArrow()
{
   if(g_mouseTime==0) return;
   string nm=UniqueName("ARW");
   // OBJ_ARROWED_LINE: linea con flecha direccional (igual al tool H4 Arrowed Line)
   // Punto 1 = 3 barras atras, punto 2 = posicion del mouse
   datetime t1 = g_mouseTime - (datetime)(3*PeriodSeconds());
   ObjectCreate(0,nm,OBJ_ARROWED_LINE,0,t1,g_mousePrice,g_mouseTime,g_mousePrice);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,     clrYellow);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,     2);
   ObjectSetInteger(0,nm,OBJPROP_STYLE,     STYLE_SOLID);
   ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,nm,OBJPROP_SELECTED,  true);
}

void DeleteManualObjects()
{
   // Los objetos del Ctrl+B (sin "List all") son los dibujados manualmente:
   // no tienen HIDDEN=true ni SELECTABLE=false simultaneamente.
   // Los objetos de indicadores/EAs se crean con ambas propiedades en ese estado.
   // Excepcion: los botones del propio panel (prefijo CTP_BTN_) se preservan.
   int total = ObjectsTotal(0);
   for(int i=total-1; i>=0; i--)
   {
      string nm = ObjectName(0,i);
      // Preservar botones del panel
      if(StringFind(nm, PREFIX+"BTN_") == 0) continue;
      // Si el objeto esta oculto Y no es seleccionable = creado por indicador/EA -> saltar
      bool hidden     = (bool)ObjectGetInteger(0, nm, OBJPROP_HIDDEN);
      bool selectable = (bool)ObjectGetInteger(0, nm, OBJPROP_SELECTABLE);
      if(hidden && !selectable) continue;
      // Todo lo demas es objeto manual -> borrar
      ObjectDelete(0, nm);
   }
   ChartRedraw();
}

void PlaceRectangle()
{
   if(g_mouseTime==0) return;
   int    psec  = PeriodSeconds();
   double range = (ChartGetDouble(0,CHART_FIXED_MAX)-ChartGetDouble(0,CHART_FIXED_MIN))*0.02;
   if(range<=0) range=g_mousePrice*0.005;
   datetime t2  = g_mouseTime  + (datetime)(3*psec);
   double   p2  = g_mousePrice - range;
   string   nm  = UniqueName("RCT");
   ObjectCreate(0,nm,OBJ_RECTANGLE,0,g_mouseTime,g_mousePrice,t2,p2);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,     clrDodgerBlue);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,     1);
   ObjectSetInteger(0,nm,OBJPROP_FILL,      false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,nm,OBJPROP_SELECTED,  true);
}

void PlaceHLine()
{
   if(g_mousePrice==0) return;
   string nm=UniqueName("HLN");
   ObjectCreate(0,nm,OBJ_HLINE,0,g_mouseTime,g_mousePrice);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,     clrAqua);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,     1);
   ObjectSetInteger(0,nm,OBJPROP_STYLE,     STYLE_SOLID);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,nm,OBJPROP_SELECTED,  true);
}

void PlaceVLine()
{
   if(g_mouseTime==0) return;
   string nm=UniqueName("VLN");
   ObjectCreate(0,nm,OBJ_VLINE,0,g_mouseTime,g_mousePrice);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,     clrOrange);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,     1);
   ObjectSetInteger(0,nm,OBJPROP_STYLE,     STYLE_SOLID);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,nm,OBJPROP_SELECTED,  true);
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lp, const double &dp, const string &sp)
{
   // Actualizar posicion del mouse en cada movimiento
   if(id==CHARTEVENT_MOUSE_MOVE)
   {
      int sw=0;
      ChartXYToTimePrice(0,(int)lp,(int)dp,sw,g_mouseTime,g_mousePrice);
      return;
   }

   if(id==CHARTEVENT_KEYDOWN)
   {
      // E = LEFTDOWN al presionar (LEFTUP se envía en OnTimer cuando se suelta)
      if((int)lp==69 && !g_eHeld) { mouse_event(MOUSEEVENTF_LEFTDOWN,0,0,0,0); g_eHeld=true; return; }
      // lp = keycode: 49='1', 50='2', 51='3', 52='4'
      switch((int)lp)
      {
         case 49: PlaceArrow();     ChartRedraw(); break;
         case 50: PlaceRectangle(); ChartRedraw(); break;
         case 51: PlaceHLine();     ChartRedraw(); break;
         case 52: PlaceVLine();     ChartRedraw(); break;
         case 55: ToggleAutoScroll();             break;  // 7 = toggle "scroll to end"
         case 56: ToggleScaleFix();               break;  // 8 = FIX
         case 57: ChartSetInteger(0,CHART_SHIFT,!(bool)ChartGetInteger(0,CHART_SHIFT)); UpdateShiftButton(); ChartRedraw(); break;  // 9 = SHF
         case 48: ToggleAutoScroll();             break;  // 0 = AS
      }
      return;
   }

   if(id==CHARTEVENT_OBJECT_CLICK)
   {
      if(ObjectFind(0,sp)>=0) ObjectSetInteger(0,sp,OBJPROP_STATE,false);
      if(sp==BFIX)    { ToggleScaleFix();                                                        return; }
      if(sp==BSCROLL) { ToggleAutoScroll();                                                     return; }
      if(sp==BSHIFT)  { ChartSetInteger(0,CHART_SHIFT,!(bool)ChartGetInteger(0,CHART_SHIFT)); UpdateShiftButton(); ChartRedraw(); return; }
      if(sp==BBEGIN)  { ChartNavigate(0,CHART_BEGIN,0); return; }
      if(sp==BTRASH)  { DeleteManualObjects();          return; }
   }

   if(id==CHARTEVENT_CHART_CHANGE)
   {
      // Reposicionar botones por si cambio el ancho de la barra de precios
      int mx = PriceScaleWidth() + 6 - 39 + 10;
      int my = 25 - 5; int W=39, H=14, GAP=3;
      if(ObjectFind(0,BFIX)>=0)   { ObjectSetInteger(0,BFIX,   OBJPROP_XDISTANCE,mx); ObjectSetInteger(0,BFIX,   OBJPROP_YDISTANCE,my); }
      if(ObjectFind(0,BSHIFT)>=0) { ObjectSetInteger(0,BSHIFT, OBJPROP_XDISTANCE,mx); ObjectSetInteger(0,BSHIFT, OBJPROP_YDISTANCE,my+(H+GAP)); }
      if(ObjectFind(0,BSCROLL)>=0){ ObjectSetInteger(0,BSCROLL,OBJPROP_XDISTANCE,mx); ObjectSetInteger(0,BSCROLL,OBJPROP_YDISTANCE,my+(H+GAP)*2); }
      if(ObjectFind(0,BBEGIN)>=0) { ObjectSetInteger(0,BBEGIN, OBJPROP_XDISTANCE,mx); ObjectSetInteger(0,BBEGIN, OBJPROP_YDISTANCE,my+(H+GAP)*3); }
      if(ObjectFind(0,BTRASH)>=0) { ObjectSetInteger(0,BTRASH, OBJPROP_XDISTANCE,mx); ObjectSetInteger(0,BTRASH, OBJPROP_YDISTANCE,my+(H+GAP)*4); }
      UpdateFixButton();
      UpdateScrollButton();
      UpdateShiftButton();
      ChartRedraw();
   }
}
//+------------------------------------------------------------------+
