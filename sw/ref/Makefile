# NPU Reference Model Makefile

CC = gcc
CFLAGS = -Wall -Wextra -O2 -g
LDFLAGS =

TARGET = npu_ref
SRCS = main.c npu_ref.c
OBJS = $(SRCS:.c=.o)

.PHONY: all clean run

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.c npu_ref.h
	$(CC) $(CFLAGS) -c -o $@ $<

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET) $(OBJS) *.hex
