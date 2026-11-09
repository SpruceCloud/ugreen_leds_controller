
CXX ?= g++
CPPFLAGS += -I.
CXXFLAGS ?= -O2 -g -Wall
CXXFLAGS += -std=c++17
DEPS = i2c.h ugreen_leds.h
OBJ = i2c.o ugreen_leds.o 

%.o: %.cpp $(DEPS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c -o $@ $<

ugreen_leds_cli: $(OBJ) ugreen_leds_cli.o
	$(CXX) $(LDFLAGS) -o $@ $^ $(LDLIBS)

.PHONY: clean
clean:
	rm -f $(OBJ) ugreen_leds_cli.o ugreen_leds_cli
