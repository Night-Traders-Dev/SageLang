CC = gcc
CFLAGS = -g -Wall -Iinclude

SRCS = $(wildcard src/*.c)
OBJS = $(SRCS:.c=.o)
TARGET = sage

$(TARGET): $(OBJS)
	$(CC) $(OBJS) -o $(TARGET)

src/%.o: src/%.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)
