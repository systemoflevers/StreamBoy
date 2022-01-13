#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecure.h>
#include <SPI.h>

#include "wifi_credentials.h"
#include "tile_data_bin.h"
#include "tile_data_bin2.h"

const byte kInputInterruptPin = 5;  // Wemos D1
const byte kIOClockPin = 14;        // Wemos D5
const byte kInputDataPin = 12;      // Wemos D6
const byte kOutputDataPin = 13;     // Wemos D7
const byte kPLStrobePin = 16;       // Wemos D0. PL is active low.
const byte kOutputInterruptPin = 0; // Wemos D3
volatile bool inputWaiting = false;
volatile bool outputWaiting = false;

// changes state to indicate ready
const byte kReadyPin = 4; // Wemos D2

auto serial = Serial1;
WiFiClient client;

unsigned char* tile_datas[] = {tile_data_bin, tile_data2_bin};
int tile_set = 1;
unsigned int tile_data_len = tile_data2_bin_len;


uint8_t status_bit = 1;
int outPlace = 0;

enum State {
  kConnecting,
  kConnected,
  kGettingTweet,
  kSendingToGB,
  kWaitingForInput,
  kWaitingForLike,
  kDone,
};
State state = kConnecting;

char data_buffer[5770];

bool use_server = true;


bool first_connection = true;
void connectWifi()
{
  if (WiFi.status() == WL_CONNECTED)
    return;

  WiFi.forceSleepWake();
  delay(1);

  if (first_connection)
  {
    WiFi.begin(WIFI_SSID, WIFI_PWD);
    first_connection = false;
  }
  else
  {
    WiFi.begin();
  }

  serial.println(F("Connecting"));
  while (WiFi.status() != WL_CONNECTED && WiFi.waitForConnectResult() != WL_CONNECTED)
  {
    delay(50);
    serial.print(".");
  }
  serial.println();

  serial.println(F("Connected, IP address: "));
  serial.println(WiFi.localIP());
}



bool connectToServer() {
  if (client.connected()) return true;

  if (client.connect("192.168.86.133", 9090)) {
    serial.println("connected to server");
    serial.println("there are this many bytes available: " + String(client.available()));
    return true;
  }

  serial.println("failed to connect to server");
  return false;
}

byte sendToServer(byte data) {
  if (!connectToServer()) return 0;

  serial.println("sending: " + String(data));
  client.write(data);

  // Wait for response to be available
  while(!client.available());
  size_t len = client.readBytes(data_buffer, tile_data_len);


  //byte fromServer = client.read();
  serial.println(String("received length: ") + len + " " + status_bit + state);
  //serial.println(data_buffer);
  return 1;
}

SPISettings inputSpiSettings(8000000, MSBFIRST, SPI_MODE0);
SPISettings outputSpiSettings(80000000, MSBFIRST, SPI_MODE0);

byte inputs[20] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
byte outputs[20] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
int inIntPin[10];
int iipc = 0;

int iC = 0;
int readInputCounter = 0;

byte to_send = 0;
void handleInputInterrupt()
{
  serial.print("i");
  if (state == kSendingToGB) {
    //byte value = readInput();
    byte value = SPI.transfer(0);
    outputWaiting = false;
    SPI.endTransaction();
    state = kWaitingForInput;
    status_bit ^= 1;
    digitalWrite(kReadyPin, status_bit);
    //byte value = spiReadInput();
    //if (value == 0) {
    //  outputWaiting = false;
    //  state = kDone;
    //}
  }
  else if (state == kWaitingForInput) {
    to_send = readInput();
    state = kDone;
  }
    serial.println(String(": ") + to_send + " " + outPlace);
  inputWaiting = true;
  return;
}
bool fastSend = false;

void handleOutputInterrupt()
{
  if (state == kDone) {
    //xserial.println(String("we're done, why are you printing ") + outPlace + "status bit: " + status_bit);
    return;
  }
  if (state == kSendingToGB) {
    /*if (outPlace >= tile_data_len) {
      SPI.endTransaction();
      //xserial.print(String("done sending ") + outPlace);
      state = kDone;
      outputWaiting = false;
      return;
    }*/
    if (use_server)
      SPI.transfer(data_buffer[outPlace]);
    else
      SPI.transfer(tile_datas[tile_set][outPlace]);

    ++outPlace;
    return;
  }
  outputWaiting = false;
  serial.print(String("|") + status_bit + state+":"+outPlace);
  status_bit = 1;
  digitalWrite(kReadyPin, status_bit);
}

bool useSpi = true;

void setupIO() {
  if (useSpi) {
    SPI.begin();
  } else {
    pinMode(kIOClockPin, OUTPUT);
    digitalWrite(kIOClockPin, LOW);
    pinMode(kInputDataPin, INPUT);
    pinMode(kOutputDataPin, OUTPUT);

    pinMode(kPLStrobePin, OUTPUT);
    digitalWrite(kPLStrobePin, LOW);
  }
}

byte readInput()
{
  if (useSpi) {
    return spiReadInput();
  }
  digitalWrite(kPLStrobePin, HIGH);
  byte v = shiftIn(kInputDataPin, kIOClockPin, MSBFIRST);
  digitalWrite(kPLStrobePin, LOW);
  digitalWrite(kIOClockPin, HIGH);
  inputWaiting = false;
  return v;
}

void writeToGB(byte data)
{
  if (useSpi) {
    spiWriteToGB(data);
    return;
  }
  serial.print((char)data);
  digitalWrite(kIOClockPin, LOW);
  shiftOut(kOutputDataPin, kIOClockPin, MSBFIRST, data);
  digitalWrite(kPLStrobePin, HIGH);
  digitalWrite(kPLStrobePin, LOW);
  //digitalWrite(kIOClockPin, HIGH);
  outputWaiting = true;
}

byte spiReadInput()
{
  SPI.beginTransaction(inputSpiSettings);
  digitalWrite(kPLStrobePin, HIGH);
  byte inData = SPI.transfer('*');
  digitalWrite(kPLStrobePin, LOW);
  SPI.endTransaction();

  return inData;
}

void spiWriteToGB(byte outData)
{
  SPI.beginTransaction(outputSpiSettings);
  byte in = SPI.transfer(outData);
  //serial.println(String("sending: ") + ((char)outData) + " got: " + ((char)in));
  //digitalWrite(kPLStrobePin, HIGH);
  //digitalWrite(kPLStrobePin, LOW);

  SPI.endTransaction();
  outputWaiting = true;
}

unsigned long t;
void setup()
{
  serial.begin(9600);
  serial.println("");
  serial.println("hi!");

  // turn off wifi modem
  WiFi.disconnect();
  //WiFi.forceSleepBegin();
  delay(100);

  // setup input control
  pinMode(kInputInterruptPin, INPUT);
  attachInterrupt(digitalPinToInterrupt(kInputInterruptPin), handleInputInterrupt, CHANGE);
  attachInterrupt(digitalPinToInterrupt(kOutputInterruptPin), handleOutputInterrupt, CHANGE);

  setupIO();

  pinMode(kReadyPin, OUTPUT);
  status_bit = HIGH;
  digitalWrite(kReadyPin, status_bit);

  connectWifi();

  if (use_server) {
    connectToServer();

    sendToServer(1);
  }

  //SPI.begin();
  //spiWriteToGB(255);
  writeToGB(255);
  status_bit = LOW;
  digitalWrite(kReadyPin, status_bit);
  state = kConnected;
  
  t = 0; //millis();
}

String getTweet(String id)
{
  String url = TWITTER_APP_URL;
  url += "read=";
  url += id;
  serial.println("[HTTP] URL: " + url);
  HTTPClient http;
  http.begin(url);
  int httpCode = http.GET();

  if (httpCode > 0)
  {
    // HTTP header has been send and Server response header has been handled
    serial.printf("[HTTP] GET... code: %d\n", httpCode);

    // file found at server
    if (httpCode == HTTP_CODE_OK)
    {
      String payload = http.getString();
      serial.println("payload:");
      serial.println(payload);
      return payload;
      serial.println("******");
      payload.trim();
      serial.println("trimmed:");
      serial.println(payload);
      
      return payload;
    }
  }
  else
  {
    serial.printf("[HTTP] GET... failed, error: %s\n", http.errorToString(httpCode).c_str());
    return "";
  }
}

String likeTweet(String id)
{
  String url = TWITTER_APP_URL;
  url += "like=";
  url = url + id;
  serial.println("[HTTP] URL: " + url);
  HTTPClient http;
  http.begin(url);
  int httpCode = http.GET();

  if (httpCode > 0)
  {
    // HTTP header has been send and Server response header has been handled
    serial.printf("[HTTP] GET... code: %d\n", httpCode);

    // file found at server
    if (httpCode == HTTP_CODE_OK)
    {
      String payload = http.getString();
      serial.println("payload:");
      serial.println(payload);
      return payload;
      serial.println("******");
      payload.trim();
      serial.println("trimmed:");
      serial.println(payload);
      
      return payload;
    }
  }
  else
  {
    serial.printf("[HTTP] GET... failed, error: %s\n", http.errorToString(httpCode).c_str());
    return "";
  }
}

String tweet = "";
int tweetPlace = 0;

// mine 1471717599096590340
String tweetId = "1471717599096590340";
//String tweetId = "1471428560846000128";
void loop()
{
  //serial.println(String("state: ") + state + " outPlace: " + outPlace + " status_bit: "+ status_bit + " output_waiting: " + outputWaiting);
  if (outputWaiting)
    return;
  if (state == kDone) {
    tile_set = (tile_set + 1) % 2;

    if (use_server)
      sendToServer(to_send);
    to_send = 0;
    outPlace = 0;
    state = kConnected;
  }

  if (state == kConnected)
  {
    serial.println("trying to get tweet");
    //tweet = getTweet(tweetId);
    //digitalWrite(kReadyPin, LOW);

    state = kSendingToGB;
    SPI.beginTransaction(outputSpiSettings);
    if (use_server)
      SPI.transfer(data_buffer[outPlace]);
    else
      SPI.transfer(tile_datas[tile_set][outPlace]);

    ++outPlace;
    outputWaiting = true;
    state = kSendingToGB;
    status_bit ^= 1;
    digitalWrite(kReadyPin, status_bit);
    return;
  }
  if (state == kSendingToGB) {
    return;
  }
  if (state == kWaitingForLike && inputWaiting) {
    //state = kDone;
    //return;
    char c = spiReadInput();
    likeTweet(tweetId);
    serial.println("did like telling gb");
    writeToGB(1);
    status_bit = LOW;
    digitalWrite(kReadyPin, status_bit);
    state = kDone;
    serial.println("done done");
    return;
  }
}