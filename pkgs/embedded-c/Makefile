# Project name
PROJECT = my_project

# MCU settings
MCU = atmega328p
F_CPU = 16000000UL

# Compiler settings
CC = avr-gcc
OBJCOPY = avr-objcopy
AVRDUDE = avrdude
CFLAGS = -Os -DF_CPU=$(F_CPU) -mmcu=$(MCU) -Wall -Werror
LDFLAGS = -mmcu=$(MCU)

# Source files
SRC = $(wildcard src/*.c)
OBJ = $(SRC:.c=.o)

# Programmer settings (adjust as needed)
PROGRAMMER = arduino
PORT = /dev/ttyACM0

# Targets
all: $(PROJECT).hex

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

$(PROJECT).elf: $(OBJ)
	$(CC) $(LDFLAGS) -o $@ $^

$(PROJECT).hex: $(PROJECT).elf
	$(OBJCOPY) -O ihex -R .eeprom $< $@

upload: $(PROJECT).hex
	$(AVRDUDE) -F -V -c $(PROGRAMMER) -p $(MCU) -P $(PORT) -b 115200 -U flash:w:$<

clean:
	rm -f src/*.o $(PROJECT).elf $(PROJECT).hex

.PHONY: all clean upload

