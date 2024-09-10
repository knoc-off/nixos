#include <avr/io.h>
#include <util/delay.h>

#define LED_PIN PB5  // Arduino Uno LED is on digital pin 13, which is PB5

int main(void) {
    // Set LED pin as output
    DDRB = 1 << LED_PIN;

    while (1) {
        // Turn LED on
        PORTB = 1 << LED_PIN;
        _delay_ms(1000);

        // Turn LED off
        PORTB = 0;
        _delay_ms(1000);
    }

    return 0;
}
