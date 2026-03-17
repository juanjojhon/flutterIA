/*
 * Edge Impulse + BLE Tennis Stroke Detector
 * For Arduino Nano 33 BLE / BLE Sense
 *
 * This code waits for a BLE connection and a start command from
 * the Flutter app before beginning stroke detection.
 *
 * Using NEW MODEL with higher accuracy: NicolasRC3008-project-1
 *
 * Stroke codes sent by BLE:
 * 1 = Ascendente
 * 2 = Derecha
 * 3 = Remate
 * 4 = Reves
 * 5 = Saque
 */

#include <NicolasRC3008-project-1_inferencing.h>
#include <Arduino_LSM9DS1.h>
#include <ArduinoBLE.h>

/* Constants for acceleration conversion */
#define CONVERT_G_TO_MS2    9.80665f
#define MAX_ACCEPTED_RANGE  2.0f

/* Debug */
static bool debug_nn = false;

/* BLE configuration */
// Service UUID
BLEService tennisService("180C");

// Characteristic for sending detected stroke (read/notify)
BLEByteCharacteristic strokeCharacteristic("2A56", BLERead | BLENotify);

// Characteristic for receiving control commands (write)
// 0 = stop recording, 1 = start recording
BLEByteCharacteristic controlCharacteristic("2A57", BLEWrite);

/* Recording state */
bool isRecording = false;

/* Stroke reporting control */
unsigned long lastStrokeTime = 0;
const unsigned long strokeCooldown = 700;   // ms between valid stroke reports
const float confidence_threshold = 0.60f;   // minimum confidence required

/* LED pins for status indication */
#define LED_CONNECTED   LED_BUILTIN
#define LED_RECORDING   LEDR   // Red LED on Nano 33 BLE Sense

/* Function prototypes */
void onControlWritten(BLEDevice central, BLECharacteristic characteristic);
void detectAndSendStroke();
void printStrokeName(int code);
float ei_get_sign(float number);

/* Setup */
void setup()
{
    Serial.begin(115200);
    delay(1000);

    Serial.println("=================================");
    Serial.println("Edge Impulse + BLE Tennis Detector");
    Serial.println("NEW MODEL: NicolasRC3008-project-1");
    Serial.println("=================================");

    // Initialize LEDs
    pinMode(LED_CONNECTED, OUTPUT);
    pinMode(LED_RECORDING, OUTPUT);

    digitalWrite(LED_CONNECTED, LOW);
    digitalWrite(LED_RECORDING, HIGH);   // RGB LED is active LOW

    /* IMU init */
    if (!IMU.begin()) {
        Serial.println("ERROR: Failed to initialize IMU!");
        while (1) {
            digitalWrite(LED_CONNECTED, HIGH);
            delay(100);
            digitalWrite(LED_CONNECTED, LOW);
            delay(100);
        }
    }
    Serial.println("IMU initialized OK");

    if (EI_CLASSIFIER_RAW_SAMPLES_PER_FRAME != 3) {
        Serial.println("ERROR: Model expects RAW_SAMPLES_PER_FRAME = 3");
        while (1) {
            digitalWrite(LED_CONNECTED, HIGH);
            delay(300);
            digitalWrite(LED_CONNECTED, LOW);
            delay(300);
        }
    }

    /* BLE init */
    if (!BLE.begin()) {
        Serial.println("ERROR: Failed to initialize BLE!");
        while (1) {
            digitalWrite(LED_CONNECTED, HIGH);
            delay(500);
            digitalWrite(LED_CONNECTED, LOW);
            delay(500);
        }
    }

    // Device name shown on phone
    BLE.setLocalName("TennisDetector");
    BLE.setAdvertisedService(tennisService);

    // Add characteristics
    tennisService.addCharacteristic(strokeCharacteristic);
    tennisService.addCharacteristic(controlCharacteristic);

    // Add service
    BLE.addService(tennisService);

    // Initial values
    strokeCharacteristic.writeValue((byte)0);
    controlCharacteristic.writeValue((byte)0);

    // Callback when app writes to control characteristic
    controlCharacteristic.setEventHandler(BLEWritten, onControlWritten);

    // Start BLE advertising
    BLE.advertise();

    Serial.println("BLE initialized OK");
    Serial.println("Device name: TennisDetector");
    Serial.println("Waiting for connections...");
    Serial.println("---------------------------------");
}

/**
 * @brief Return the sign of the number
 * 
 * @param number 
 * @return float 1.0 if positive (or 0) -1.0 if negative
 */
float ei_get_sign(float number) {
    return (number >= 0.0) ? 1.0 : -1.0;
}

/* Callback when control characteristic is written */
void onControlWritten(BLEDevice central, BLECharacteristic characteristic)
{
    byte value = controlCharacteristic.value();

    if (value == 1) {
        isRecording = true;
        digitalWrite(LED_RECORDING, LOW);   // ON
        Serial.println(">>> Recording STARTED");
    }
    else {
        isRecording = false;
        digitalWrite(LED_RECORDING, HIGH);  // OFF
        Serial.println(">>> Recording STOPPED");
    }
}

/* Main loop */
void loop()
{
    BLE.poll();

    BLEDevice central = BLE.central();

    if (central) {
        digitalWrite(LED_CONNECTED, HIGH);

        Serial.print("Connected to: ");
        Serial.println(central.address());

        while (central.connected()) {
            BLE.poll();

            if (isRecording) {
                detectAndSendStroke();
            }
            else {
                delay(50);
            }
        }

        // Reset state on disconnect
        digitalWrite(LED_CONNECTED, LOW);
        digitalWrite(LED_RECORDING, HIGH);
        isRecording = false;

        Serial.println("Device disconnected");
        Serial.println("Waiting for connections...");
        Serial.println("---------------------------------");
    }
}

/* Detect stroke and send via BLE */
void detectAndSendStroke()
{
    float buffer[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE] = {0};

    Serial.println("Sampling accelerometer data...");

    // This model uses m/s^2 conversion (like Edge Impulse default)
    for (size_t ix = 0; ix < EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE; ix += 3) {
        uint64_t next_tick = micros() + (EI_CLASSIFIER_INTERVAL_MS * 1000);

        // Read acceleration in g
        IMU.readAcceleration(buffer[ix], buffer[ix + 1], buffer[ix + 2]);

        // Clamp to MAX_ACCEPTED_RANGE
        for (int i = 0; i < 3; i++) {
            if (fabs(buffer[ix + i]) > MAX_ACCEPTED_RANGE) {
                buffer[ix + i] = ei_get_sign(buffer[ix + i]) * MAX_ACCEPTED_RANGE;
            }
        }

        // Convert g to m/s^2
        buffer[ix + 0] *= CONVERT_G_TO_MS2;
        buffer[ix + 1] *= CONVERT_G_TO_MS2;
        buffer[ix + 2] *= CONVERT_G_TO_MS2;

        // Wait until next sample time
        delayMicroseconds(next_tick - micros());
    }

    /* Convert buffer to signal */
    signal_t signal;
    int err = numpy::signal_from_buffer(
        buffer,
        EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE,
        &signal
    );

    if (err != 0) {
        Serial.print("ERROR: Failed to create signal from buffer. Code: ");
        Serial.println(err);
        return;
    }

    /* Run Edge Impulse classifier */
    ei_impulse_result_t result = {0};

    err = run_classifier(&signal, &result, debug_nn);

    if (err != EI_IMPULSE_OK) {
        Serial.print("ERROR: Classifier failed with code ");
        Serial.println(err);
        return;
    }

    /* Find highest confidence prediction */
    int golpe = 0;
    float max_val = 0.0f;

    Serial.println("Predictions:");

    for (size_t ix = 0; ix < EI_CLASSIFIER_LABEL_COUNT; ix++) {
        const char *label = result.classification[ix].label;
        float value = result.classification[ix].value;

        Serial.print("  ");
        Serial.print(label);
        Serial.print(": ");
        Serial.println(value, 4);

        if (value > max_val) {
            max_val = value;

            if (strcmp(label, "ascendente") == 0) {
                golpe = 1;
            }
            else if (strcmp(label, "derecha") == 0) {
                golpe = 2;
            }
            else if (strcmp(label, "remate") == 0) {
                golpe = 3;
            }
            else if (strcmp(label, "reves") == 0) {
                golpe = 4;
            }
            else if (strcmp(label, "saque") == 0) {
                golpe = 5;
            }
            else {
                golpe = 0;
            }
        }
    }

    /* Send result via BLE only if confidence is high enough and cooldown passed */
    if (golpe != 0 && max_val >= confidence_threshold) {

        if (millis() - lastStrokeTime >= strokeCooldown) {

            if (strokeCharacteristic.subscribed()) {
                strokeCharacteristic.writeValue((byte)golpe);
            }

            lastStrokeTime = millis();

            Serial.print(">>> Stroke detected: ");
            printStrokeName(golpe);
            Serial.print(" (confidence: ");
            Serial.print(max_val * 100.0f, 1);
            Serial.println("%)");
        }
        else {
            Serial.println("Stroke ignored due to cooldown");
        }
    }
    else {
        Serial.println("No confident stroke detected");
    }

    Serial.println("---------------------------------");
}

/* Helper function to print stroke name */
void printStrokeName(int code)
{
    switch (code) {
        case 1:
            Serial.print("Ascendente");
            break;
        case 2:
            Serial.print("Derecha");
            break;
        case 3:
            Serial.print("Remate");
            break;
        case 4:
            Serial.print("Reves");
            break;
        case 5:
            Serial.print("Saque");
            break;
        default:
            Serial.print("Desconocido");
            break;
    }
}

#if !defined(EI_CLASSIFIER_SENSOR) || EI_CLASSIFIER_SENSOR != EI_CLASSIFIER_SENSOR_ACCELEROMETER
#error "Invalid model for current sensor"
#endif
