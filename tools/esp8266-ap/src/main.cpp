// Test access point for sunstone's Wi-Fi reconnect tests. Serial commands (115200, one per line):
//   on [CH]   start the AP (WPA2, default channel 6)     off      stop it (stations see it vanish)
//   status    AP state and the stations with their addresses
// Station joins and leaves are printed as they happen, with a millisecond timestamp.
#include <ESP8266WiFi.h>

static WiFiEventHandler joined, left;
static bool up;
static int channel = 6;

static void ap_on(int ch)
{
	channel = ch;
	up = WiFi.softAP(AP_SSID, AP_PASS, channel);
	Serial.printf("%lu ap %s ch %d %s\n", millis(), up ? "on" : "FAILED", channel,
		      WiFi.softAPIP().toString().c_str());
}

static void ap_off()
{
	WiFi.softAPdisconnect(true);
	up = false;
	Serial.printf("%lu ap off\n", millis());
}

static void status()
{
	Serial.printf("%lu status ap=%s ch=%d stations=%d\n", millis(), up ? "on" : "off", channel,
		      WiFi.softAPgetStationNum());
	for (station_info *s = wifi_softap_get_station_info(); s; s = STAILQ_NEXT(s, next))
		Serial.printf("  " MACSTR " %s\n", MAC2STR(s->bssid), IPAddress(s->ip.addr).toString().c_str());
	wifi_softap_free_station_info();
}

void setup()
{
	Serial.begin(115200);
	WiFi.persistent(false);
	WiFi.mode(WIFI_AP);
	joined = WiFi.onSoftAPModeStationConnected([](const WiFiEventSoftAPModeStationConnected &e) {
		Serial.printf("%lu join " MACSTR "\n", millis(), MAC2STR(e.mac));
	});
	left = WiFi.onSoftAPModeStationDisconnected([](const WiFiEventSoftAPModeStationDisconnected &e) {
		Serial.printf("%lu leave " MACSTR "\n", millis(), MAC2STR(e.mac));
	});
	ap_on(channel);
}

void loop()
{
	static String line;
	while (Serial.available()) {
		char c = Serial.read();
		if (c != '\n' && c != '\r') {
			line += c;
			continue;
		}
		line.trim();
		if (line == "off")
			ap_off();
		else if (line.startsWith("on"))
			ap_on(line.length() > 3 ? line.substring(3).toInt() : channel);
		else if (line == "status")
			status();
		else if (line.length())
			Serial.printf("%lu ? %s\n", millis(), line.c_str());
		line = "";
	}
}
