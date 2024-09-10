#include <avr/io.h>
#include <util/delay.h>

#define LED_PIN PB1  // Digispark's onboard LED is on PB1 (physical pin 6)

int main() {
    // Set LED pin as output
    DDRB |= (1 << LED_PIN);

    while (1) {
        // Turn LED on
        PORTB |= (1 << LED_PIN);
        _delay_ms(5000);  // Wait for 500 milliseconds

        // Turn LED off
        PORTB &= ~(1 << LED_PIN);
        _delay_ms(500);  // Wait for 500 milliseconds
    }

    return 0;
}
