# Compiler and flags
CC = gcc
CFLAGS = -Wall -Wextra -std=c11 -g
LDFLAGS =

# Directories
SRC_DIR = src
LIB_DIR = src/lib
BUILD_DIR = src/build

# Source files
SOURCES = $(SRC_DIR)/sage.c $(LIB_DIR)/lexer.c $(LIB_DIR)/parser.c $(LIB_DIR)/codegen.c

# Object files
OBJECTS = $(patsubst %.c, %.o, $(SOURCES))

# Output binary
TARGET = sage_compiler

# Default target
all: $(TARGET)

# Build the compiler
$(TARGET): $(OBJECTS)
	$(CC) $(CFLAGS) $(OBJECTS) -o $(TARGET) $(LDFLAGS)

# Compile source files into object files
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Clean build files
clean:
	rm -f $(TARGET) $(OBJECTS)
	rm -rf $(BUILD_DIR)

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Rebuild everything
rebuild: clean all
