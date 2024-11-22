# Compiler and flags
CC = gcc
CFLAGS = -Wall -Wextra -std=c11
CFLAGSDEBUG = -Wall -Wextra -std=c11 -g
LDFLAGS =

# Directories
SRC_DIR = .
LIB_DIR = $(SRC_DIR)/lib
ARM_DIR = $(SRC_DIR)/sage_arm
RISC_DIR = $(SRC_DIR)/sage_risc
BUILD_DIR = build

# Source files
SOURCES = $(SRC_DIR)/sage_compiler.c \
          $(LIB_DIR)/tokenizer.c \
          $(LIB_DIR)/parser.c \
          $(ARM_DIR)/sage_arm.c \
          $(RISC_DIR)/sage_risc.c

# Object files
OBJECTS = $(patsubst %.c, %.o, $(SOURCES))

# Output binary
TARGET = sage_compiler

# Default target
all: $(TARGET)

# Build the main executable
$(TARGET): $(OBJECTS)
	$(CC) $(CFLAGS) $(OBJECTS) -o $(TARGET) $(LDFLAGS)

# Compile source files into object files
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Debug target
debug: CFLAGS=$(CFLAGSDEBUG)
debug: clean $(TARGET)

# Clean build files
clean:
	rm -f $(TARGET) $(OBJECTS)
	rm -rf $(BUILD_DIR)

# Rebuild everything
rebuild: clean all
