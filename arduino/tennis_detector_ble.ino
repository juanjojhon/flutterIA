/* 
 * Edge Impulse + BLE Tennis Stroke Detector
 * For Arduino Nano 33 BLE
 * 
 * This code waits for a BLE connection and a start command from
 * the Flutter app before beginning stroke detection.
 * 
 * Golpes detectados:
 * 1 = Ascendente
 * 2 = Derecha
 * 3 = Remate
 * 4 = Reves
 * 5 = Saque
 */

#include <NicolasR3008-project-1_inferencing.h>
#include <Arduino_LSM9DS1.h>
#include <ArduinoBLE.h>

/* Constants */
#define CONVERT_G_TO_MS2 9.80665f
#define MAX_ACCEPTED_RANGE 2.0f

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

/* LED pins for status indication */
#define LED_CONNECTED   LED_BUILTIN
#define LED_RECORDING   LEDR  // Red LED for recording status

/* Setup */
void setup()
{
    Serial.begin(115200);
    // Don't wait for serial in production
    delay(1000);

    Serial.println("=================================");
    Serial.println("Edge Impulse + BLE Tennis Detector");
    Serial.println("=================================");

    // Initialize LEDs
    pinMode(LED_CONNECTED, OUTPUT);
    pinMode(LED_RECORDING, OUTPUT);
    digitalWrite(LED_CONNECTED, LOW);
    digitalWrite(LED_RECORDING, HIGH);  // HIGH = OFF for RGB LED

    /* IMU init */
    if (!IMU.begin()) {
        Serial.println("ERROR: Failed to initialize IMU!");
        while (1) {
            // Blink LED to indicate error
            digitalWrite(LED_CONNECTED, HIGH);
            delay(100);
            digitalWrite(LED_CONNECTED, LOW);
            delay(100);
        }
    }
    Serial.println("IMU initialized OK");

    /* BLE init */
    if (!BLE.begin()) {
        Serial.println("ERROR: Failed to initialize BLE!");
        while (1) {
            // Blink LED to indicate error
            digitalWrite(LED_CONNECTED, HIGH);
            delay(500);
            digitalWrite(LED_CONNECTED, LOW);
            delay(500);
        }
    }

    // Set BLE device name and advertised service
    BLE.setLocalName("TennisDetector");
    BLE.setAdvertisedService(tennisService);

    // Add characteristics to service
    tennisService.addCharacteristic(strokeCharacteristic);
    tennisService.addCharacteristic(controlCharacteristic);
    
    // Add service
    BLE.addService(tennisService);

    // Initialize characteristic values
    strokeCharacteristic.writeValue(0);
    controlCharacteristic.writeValue(0);

    // Set event handler for control characteristic
    controlCharacteristic.setEventHandler(BLEWritten, onControlWritten);

    // Start advertising
    BLE.advertise();

    Serial.println("BLE initialized OK");
    Serial.println("Device name: TennisDetector");
    Serial.println("Waiting for connections...");
    Serial.println("---------------------------------");
}

/* Callback when control characteristic is written */
void onControlWritten(BLEDevice central, BLECharacteristic characteristic) {
    byte value = controlCharacteristic.value();
    
    if (value == 1) {
        isRecording = true;
        digitalWrite(LED_RECORDING, LOW);  // LOW = ON for RGB LED
        Serial.println(">>> Recording STARTED");
    } else {
        isRecording = false;
        digitalWrite(LED_RECORDING, HIGH);  // HIGH = OFF for RGB LED
        Serial.println(">>> Recording STOPPED");
    }
}

/* Sign helper function */
float ei_get_sign(float number) {
    return (number >= 0.0) ? 1.0 : -1.0;
}

/* Main loop */
void loop()
{
    // Poll for BLE events
    BLE.poll();
    
    BLEDevice central = BLE.central();

    if (central) {
        // Device connected
        digitalWrite(LED_CONNECTED, HIGH);
        Serial.print("Connected to: ");
        Serial.println(central.address());

        while (central.connected()) {
            // Poll for BLE events
            BLE.poll();
            
            // Only detect strokes if recording is enabled
            if (isRecording) {
                detectAndSendStroke();
            } else {
                // Small delay when not recording to avoid busy loop
                delay(50);
            }
        }

        // Device disconnected
        digitalWrite(LED_CONNECTED, LOW);
        digitalWrite(LED_RECORDING, HIGH);  // Turn off recording LED
        isRecording = false;
        
        Serial.println("Device disconnected");
        Serial.println("Waiting for connections...");
    }
}

/* Detect stroke and send via BLE */
void detectAndSendStroke() {
    float buffer[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE] = {0};

    Serial.println("Sampling accelerometer data...");

    /* Collect accelerometer data */
    for (size_t ix = 0; ix < EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE; ix += 3) {
        uint64_t next_tick = micros() + (EI_CLASSIFIER_INTERVAL_MS * 1000);

        // Read acceleration values
        IMU.readAcceleration(buffer[ix], buffer[ix + 1], buffer[ix + 2]);

        // Clamp values to accepted range
        for (int i = 0; i < 3; i++) {
            if (fabs(buffer[ix + i]) > MAX_ACCEPTED_RANGE) {
                buffer[ix + i] = ei_get_sign(buffer[ix + i]) * MAX_ACCEPTED_RANGE;
            }
        }

        // Convert from g to m/s^2
        buffer[ix + 0] *= CONVERT_G_TO_MS2;
        buffer[ix + 1] *= CONVERT_G_TO_MS2;
        buffer[ix + 2] *= CONVERT_G_TO_MS2;

        // Wait for next sample time
        while (micros() < next_tick) {
            delayMicroseconds(10);
        }
    }

    /* Convert buffer to signal */
    signal_t signal;
    int err = numpy::signal_from_buffer(
        buffer,
        EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE,
        &signal
    );

    if (err != 0) {
        Serial.println("ERROR: Failed to create signal from buffer");
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

    /* Find the highest confidence prediction */
    int golpe = 0;
    float max_val = 0.0;
    float confidence_threshold = 0.6;  // Minimum confidence to report a stroke

    Serial.println("Predictions:");
    
    for (size_t ix = 0; ix < EI_CLASSIFIER_LABEL_COUNT; ix++) {
        Serial.print("  ");
        Serial.print(result.classification[ix].label);
        Serial.print(": ");
        Serial.println(result.classification[ix].value, 4);

        if (result.classification[ix].value > max_val) {
            max_val = result.classification[ix].value;

            // Map label to stroke code
            if (strcmp(result.classification[ix].label, "ascendente") == 0)
                golpe = 1;
            else if (strcmp(result.classification[ix].label, "derecha") == 0)
                golpe = 2;
            else if (strcmp(result.classification[ix].label, "remate") == 0)
                golpe = 3;
            else if (strcmp(result.classification[ix].label, "reves") == 0)
                golpe = 4;
            else if (strcmp(result.classification[ix].label, "saque") == 0)
                golpe = 5;
            else
                golpe = 0;  // Unknown or idle
        }
    }

    /* Send result via BLE only if confidence is high enough */
    if (golpe != 0 && max_val >= confidence_threshold) {
        strokeCharacteristic.writeValue(golpe);
        
        Serial.print(">>> Stroke detected: ");
        printStrokeName(golpe);
        Serial.print(" (confidence: ");
        Serial.print(max_val * 100, 1);
        Serial.println("%)");
    } else {
        Serial.println("No confident stroke detected");
    }
    
    Serial.println("---------------------------------");
}

/* Helper function to print stroke name */
void printStrokeName(int code) {
    switch (code) {
        case 1: Serial.print("Ascendente"); break;
        case 2: Serial.print("Derecha"); break;
        case 3: Serial.print("Remate"); break;
        case 4: Serial.print("Reves"); break;
        case 5: Serial.print("Saque"); break;
        default: Serial.print("Desconocido"); break;
    }
}
