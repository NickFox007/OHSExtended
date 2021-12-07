#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <colors>
#undef REQUIRE_PLUGIN
#tryinclude <adminmenu>
#pragma newdecls required

public Plugin myinfo = 
{
	name = "Only headshots Extended",
	author = "NickFox",
	description = "Prevents all damage but headshots while mode is enabled and has lots of options for this.",
	version = "1.1.0",
	url = "http://vk.com/nf_dev"
}

TopMenu	g_hTopMenu;
bool g_always = false; // Включен ли OnlyHS постоянно
bool g_knife = true; // Включен ли урон ножом во время работы режима
bool g_grens = true; // Включен ли урон гранатами во время работы режима
bool g_vote = true; // Разрешено ли голосование
bool g_enabled = false; // Включен ли OnlyHS В данный момент
bool g_adEnabled = true; // Статус работы оповещения
int g_adDelay = 1; // Задержка для оповещений
int g_Need = 65; // Сколько необходимо процентов проголосовавших для старта режима
int g_rounds = 5; // Сколько раундов должен длиться режим при запуске
int g_delay = 5; // Перерыв между битвами (раунды)
int admflag = ADMFLAG_CUSTOM5; // Выбор флага доступа (по умолчанию - флаг S)

int roundTimer = -1; // Отсчет раундов после начала карты (время битвы)
int delayTimer = 3; // Отсчет раундов после начала карты (кулдаун)
int adTimer = 1; // Отсчет раундов для оповещений

Handle g_Cvaralways = INVALID_HANDLE;
Handle g_Cvarknife = INVALID_HANDLE;
Handle g_Cvargrens = INVALID_HANDLE;
Handle g_Cvarvote = INVALID_HANDLE;
Handle g_Cvarneed = INVALID_HANDLE;
Handle g_Cvarrounds = INVALID_HANDLE;
Handle g_Cvardelay = INVALID_HANDLE;
Handle g_CvaradDelay = INVALID_HANDLE;
Handle g_CvaradEnabled = INVALID_HANDLE;
//Хэндлы для конваров

int g_iHealth, g_Armor; // Для хранения необходимых оффсетов
char sBuffer[256]; // Для хранения форматированного текста
bool voted[65] = false; // "Таблица" проголосовавших

char g_Prefix[40] = "{darkred}[{lime}OnlyHS{darkred}]{grey}";

public void OnPluginStart()
{

  g_iHealth = FindSendPropInfo("CCSPlayer", "m_iHealth");
  if (g_iHealth == -1)
  {
    SetFailState("[OHSExt] Error - Unable to get offset for CSSPlayer::m_iHealth");
  }
  g_Armor = FindSendPropInfo("CCSPlayer", "m_ArmorValue");
  if (g_Armor == -1)
  {
    SetFailState("[OHSExt] Error - Unable to get offset for CSSPlayer::m_ArmorValue");
  }

  //LoadTranslations("onlyhs.phrases");
  
  g_Cvaralways = CreateConVar("sm_onlyhs_always", "0", "Включение режима только головы по умолчанию. 1- ВКЛ, 0 = ВЫКЛ",_, true, 0.0, true, 1.0);
  g_Cvarknife = CreateConVar("sm_onlyhs_knife", "1", "Включение урона ножом. 1- ВКЛ, 0 = ВЫКЛ",_, true, 0.0, true, 1.0);  
  g_CvaradEnabled = CreateConVar("sm_onlyhs_adEnable", "1", "Включение оповещения о наличии команды. 1- ВКЛ, 0 = ВЫКЛ",_, true, 0.0, true, 1.0);
  g_Cvargrens = CreateConVar("sm_onlyhs_grens", "1", "Включение урона от гранат при активации режима. 1- ВКЛ, 0 = ВЫКЛ",_, true, 0.0, true, 1.0);
  g_CvaradDelay = CreateConVar("sm_onlyhs_adDelay", "1", "Задержка между раундами для оповещения");
  g_Cvarvote = CreateConVar("sm_onlyhs_vote", "1", "Включение голосования за данный режим. 1- ВКЛ, 0 = ВЫКЛ",_, true, 0.0, true, 1.0);
  g_Cvarneed = CreateConVar("sm_onlyhs_need", "60", "Количество проголосовавших, необходимых для старта режима, выраженное в процентах. Число от 1 до 100",_, true, 1.0, true, 100.0);
  g_Cvarrounds = CreateConVar("sm_onlyhs_rounds", "5", "Количество раундов в случае старта режима");
  g_Cvardelay = CreateConVar("sm_onlyhs_delay", "5", "Количество раундов, через которое можно будет начать повторное голосование");
  
  HookConVarChange(g_Cvaralways, OnSettingChanged);
  HookConVarChange(g_Cvarknife, OnSettingChanged);
  HookConVarChange(g_Cvargrens, OnSettingChanged);
  HookConVarChange(g_Cvarvote, OnSettingChanged);
  HookConVarChange(g_Cvarneed, OnSettingChanged);
  HookConVarChange(g_Cvarrounds, OnSettingChanged);
  HookConVarChange(g_Cvardelay, OnSettingChanged);  
  HookConVarChange(g_CvaradEnabled, OnSettingChanged);
  HookConVarChange(g_CvaradDelay, OnSettingChanged);

  HookEvent("round_freeze_end", RoundFreezeEnd, EventHookMode_PostNoCopy);

  RegConsoleCmd("sm_stophs", Cmd_Stop);
  RegConsoleCmd("sm_starths", Cmd_Start);
  RegConsoleCmd("sm_onlyhs", Cmd_Menu);
  RegConsoleCmd("sm_ohv", Cmd_Vote);
  RegConsoleCmd("sm_hv", Cmd_Vote);
  RegConsoleCmd("sm_head", Cmd_Vote);

  AutoExecConfig(true, "onlyhs_extended");

  if(LibraryExists("adminmenu"))
  {
	TopMenu hTopMenu;
	if((hTopMenu = GetAdminTopMenu())) OnAdminMenuReady(hTopMenu);
  }
  for(int i= 1; i <= MaxClients; i++) if(IsClientInGame(i)&&!IsFakeClient(i)) SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnMapStart(){

	setNull();
}

public void OnAdminMenuReady(Handle aTopMenu)
{
	TopMenu hTopMenu = TopMenu.FromHandle(aTopMenu);
	if(hTopMenu == g_hTopMenu) return;

	g_hTopMenu = hTopMenu;
	TopMenuObject hMyCategory = g_hTopMenu.FindCategory(ADMINMENU_SERVERCOMMANDS);
	if(hMyCategory == INVALID_TOPMENUOBJECT) return;

	// Теперь можем добавить пункты
	g_hTopMenu.AddItem("onlyhs_menu", Handler_Menu, hMyCategory, "sm_hs", admflag, "OnlyHS");
/*
*	"checkinfo_menu"	- уникальное имя пункта
*	Handler_MenuCheck	- обработчик событий
*	hMyCategory			- Объект категории в которую должен быть добавлен пункт
*	"sm_check"			- команда(для access overrides)
*	ADMFLAG_GENERIC		- Флаг доступа по умолчанию(изначально - b)
*	"OnlyHS"			- Описание пункта(опционально)
*/
}

public void Handler_Menu(TopMenu hMenu, TopMenuAction action, TopMenuObject object_id, int iClient, char[] sdBuffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:	FormatEx(sdBuffer, maxlength, "Битва на головах"); // Когда категория отображается пунктом на главной странице админ-меню
		case TopMenuAction_DisplayTitle:	FormatEx(sdBuffer, maxlength, "Выберите команду"); // Когда категория отображается заглавием текущего меню
		case TopMenuAction_SelectOption:	DisplayHSMenu(iClient); // Показываем меню выбора игрока
	}
}

public void DisplayHSMenu(int client) // Функция показа меню с выбором игрока
{
	Menu menu = new Menu(MenuHandler_OnlyHS); // Прикрепляем обработчик при выборе в категории
	menu.SetTitle("Выберите команду"); // Устанавливаем заголовок
	menu.ExitBackButton = true; // Активируем кнопку выхода	
	menu.AddItem("item1","Начать битву");
	menu.AddItem("item2","Закончить битву");
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_OnlyHS(Menu menu, MenuAction action, int client, int iItem)
{
	if(action == MenuAction_End)
		delete menu; // Выход из меню
	else if(action == MenuAction_Select) // Если игрок был выбран
	{		
		if (isAdmin(client)){
			if (iItem==0){ startHS(client); DisplayHSMenu(client); }
			if (iItem==1){ stopHS(client); DisplayHSMenu(client);}
		}
	}
	else if(action == MenuAction_Cancel && iItem == MenuCancel_ExitBack && g_hTopMenu)
		g_hTopMenu.Display(client, TopMenuPosition_LastCategory); // Вернуться в предыдущую категорию
}



public void OnLibraryRemoved(const char[] szName) 
{  	
	if(StrEqual(szName, "adminmenu"))
		g_hTopMenu = null;
}


public bool isAdmin(int i){
	if(CheckCommandAccess(i, "BypassPremiumCheck", admflag, true))return true;
	else return false;
}


public void OnSettingChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
  if (convar == g_Cvaralways)
  {
    if (newValue[0] == '1')
    {
		g_always = true;			
    }
    else
    {
		g_always = false;     
    }
  }
  if (convar == g_Cvarknife)
  {
    if (newValue[0] == '1')
    {
		g_knife = true;		
    }
    else
    {
		g_knife = false;      
    }
  }
  if (convar == g_Cvargrens)
  {
    if (newValue[0] == '1')
    {
		g_grens = true;		
    }
    else
    {
		g_grens = false;      
    }
  }
  if (convar == g_Cvarvote)
  {
    if (newValue[0] == '1')
    {
		g_vote = true;		
    }
    else
    {
		g_vote = false;      
    }
  }
  if (convar == g_CvaradEnabled)
  {
    if (newValue[0] == '1')
    {
		g_adEnabled = true;		
    }
    else
    {
		g_adEnabled = false;      
    }
  }
  if (convar == g_Cvarneed)
  {
	g_Need = StringToInt(newValue);
  }  
  if (convar == g_Cvarrounds)
  {
	g_rounds = StringToInt(newValue);
  }  
  if (convar == g_Cvardelay)
  {
	g_delay = StringToInt(newValue);
  }   
  if (convar == g_CvaradDelay)
  {
	g_adDelay = StringToInt(newValue);
  }  
}

public Action Cmd_Vote(int client, int args){

	if(!g_vote) PrintChat(client,"Голосование выключено Администратором");
	else if(delayTimer>0){
		Format(sBuffer, sizeof(sBuffer),"Необходимо подождать перед следующим голосованием. Осталось ждать раундов: {lime}%u",delayTimer);
		PrintChat(client,sBuffer);
	}
	else if(g_always||g_enabled) PrintChat(client,"Битва уже в самом разгаре!");
	else checkVote(client);
	
	return Plugin_Handled;

}

public int checkWeapon(char[] name){
	if (StrEqual(name,"inferno")) return 2;
	if (StrContains(name,"knife")!=-1) return 1;
	if (StrEqual(name,"hegrenade")) return 2;
	if (StrEqual(name,"flashbang")) return 2;
	if (StrEqual(name,"smokegrenade")) return 2;
	return 0;
}

public bool IsValidClient(int client){

	return (client>0&&client<65&&IsClientInGame(client));

}

public Action OnTakeDamage(int iVictim, int &iAttacker, int &iInflictor, float &fDamage, int &iDamageType, int &iWeapon, float fDamageForce[3], float fDamagePosition[3], int iDamageCustom)
{
  if ((g_always||g_enabled)&&IsValidClient(iInflictor))
  {	
	char sWeapon[32];
	GetClientWeapon(iInflictor, sWeapon, sizeof(sWeapon));
	
	if ((g_knife && checkWeapon(sWeapon)==1)||(g_grens && checkWeapon(sWeapon)==2))
	{    
		//PrintToChatAll("%s || %u",sWeapon,checkWeapon(sWeapon));
		return Plugin_Continue;
	}
	
	
	if(iDamageType & CS_DMG_HEADSHOT) return Plugin_Continue;


	if (iAttacker != iVictim)
	{
		
		return Plugin_Handled;
    }
	
  }
  return Plugin_Continue;
}

public void RoundFreezeEnd(Event event, const char[] name, bool dbc)
{
	if(roundTimer>-1){		
		if (roundTimer==0)stopHS(-1);		
		else{
			g_enabled = true;
			Format(sBuffer, sizeof(sBuffer),"Включен режим Only Headshots. До конца битвы осталось раундов: {lime}%u",roundTimer);
			PrintChat(-1,sBuffer);
			roundTimer--;
		}
		
	}
	if(delayTimer>-1)delayTimer--;
	if (roundTimer==-1&&delayTimer==-1&&g_adEnabled){
		if (adTimer==0)ad();
		if (adTimer>-1)adTimer--;		
	}
	
	
}
public void ad(){

	adTimer=g_adDelay;	
	PrintChat(-1,"На сервере доступна битва на головах. Чтобы проголосовать за её начало - пишите {darkred}!ohv");

}


public void PrintChat(int i, char[] text){

	if (i!=-1) CPrintToChat(i, "%s %s",g_Prefix,text);
	else CPrintToChatAll("%s %s",g_Prefix,text);

}

public void stopHS(int i){

	if (g_enabled&&roundTimer>-1){
		g_enabled=false;
		roundTimer=-1;
		setNull();
		PrintChat(-1,"Битва на головах завершена!");
	}
	else if (!g_enabled&&roundTimer>-1){
		roundTimer=-1;
		setNull();
		PrintChat(-1,"Битва на головах отменена!");
	}
	else if (!g_enabled&&roundTimer==-1){
		PrintChat(i,"Битва не запущена. Остановка не требуется");
	}
	

}

public void setNull(){
	for(int i= 1; i <= MaxClients; i++)voted[i]=false;
	delayTimer = g_delay;
}

public void OnConfigsExecuted()
{
  g_always = GetConVarBool(g_Cvaralways);
  g_knife = GetConVarBool(g_Cvarknife);
  g_Need = GetConVarInt(g_Cvarneed);  
  g_vote = GetConVarBool(g_Cvarvote);
  g_rounds = GetConVarInt(g_Cvarrounds);
}

public Action Cmd_Start(int client, int args){

	if (isAdmin(client)){
		startHS(client);
		return Plugin_Handled;
	}
	else return Plugin_Continue;
	
}

public Action Cmd_Stop(int client, int args){

	if (isAdmin(client)){
		stopHS(client);
		return Plugin_Handled;
	}
	else return Plugin_Continue;	
}

public Action Cmd_Menu(int client, int args){

	if (isAdmin(client)){
		DisplayHSMenu(client);
		return Plugin_Handled;
	}
	else return Plugin_Continue;
	
}

public void startHS(int i){
	if(g_enabled||g_always)PrintChat(i,"Битва уже началась. Повторная команда не требуется");
	else if (roundTimer>-1){
		PrintChat(-1,"Принудительное включение режима OnlyHS прямо сейчас");
		g_enabled=true;
	}
	else if (!g_enabled){
		roundTimer=g_rounds;	
		PrintChat(-1,"Битва на головах скоро начнется...");
	}
	
}
public void OnClientPutInServer(int client){
	voted[client] = false;
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client){
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void checkVote(int client){

	if (voted[client]) PrintChat(client,"Вы уже голосовали");
	else if (roundTimer>-1)PrintChat(client,"Битва скоро начнется. Голосование не требуется");
	else {
		int count = 0;
		int online = 0;
		voted[client] = true;		
		for(int i= 1; i <= MaxClients; i++) if(IsClientInGame(i) && !IsFakeClient(i)){
			online++;
			if(voted[i]) count++;
		}
		int need = g_Need*online/100;
		if (count>=need) startHS(-1);		
		else{			
			Format(sBuffer, sizeof(sBuffer),"%u/%u игроков проголосовало за режим Only Headshot. Необходимо ещё %u",count,need,need-count);
			PrintChat(-1,sBuffer);
		}
	}
}


