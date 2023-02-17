CC ?= gcc

OBJDIR ?= obj
SRCDIR ?= src

PACKAGES = libdeflate
LIBS =
INCS = -Isrc/
CFG = -std=gnu11 -fms-extensions -flto -lm
LDFLAGS ?= -Wl,-O3 -Wl,--as-needed -Wl,--export-dynamic -flto

ifeq "$(CFG_DEV)" ""
  CFLAGS ?= -DNDEBUG -O3 -D_FORTIFY_SOURCE=2
else ifeq "$(CFG_DEV)" "p"
  CFLAGS += -O0 -g -Wshadow -Wno-microsoft-anon-tag
else
  CFLAGS += -O0 -g -Wshadow -Wno-microsoft-anon-tag -DDEBUG_WINDOWS 
  endif
CFLAGS += -Wall

print-%  : ; @echo $* = $($*)

SOURCES = $(shell find $(SRCDIR) -name "*.c")
OBJS_C = $(SOURCES:%.c=$(OBJDIR)/%.o)
DEPS_C = $(OBJS_C:%.o=%.d)

TEST_SOURCES = $(wildcard test/*.c)
TEST_OBJS_C = $(TEST_SOURCES:%.c=$(OBJDIR)/%.o)
TEST_DEPS_C = $(TEST_OBJS_C:%.o=%.d)

LIBS += $(shell pkg-config --libs $(PACKAGES))
INCS += $(shell pkg-config --cflags $(PACKAGES))

-include $(DEPS_C) $(TEST_DEPS_C)

.DEFAULT_GOAL := index

index: $(OBJS_C)
	$(CC) $(CFG) $(CPPFLAGS) $(LDFLAGS) $(CFLAGS) -o $@ $(OBJS_C) $(LIBS)

$(OBJDIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFG) $(CPPFLAGS) $(CFLAGS) $(INCS) -MMD -o $@ -c $<

.PHONY: clean
clean:
	@rm -rf $(OBJDIR)
	@rm -f $(OBJDIR)/test/test
	@rm -f indx

$(OBJDIR)/test/test: $(TEST_OBJS_C) $(filter-out $(OBJDIR)/$(SRCDIR)/main.o, $(OBJS_C))
	$(CC) $(CFG) $(CPPFLAGS) $(LDFLAGS) $(CFLAGS) -o $@ $(TEST_OBJS_C) $(filter-out $(OBJDIR)/$(SRCDIR)/main.o, $(OBJS_C)) $(LIBS)

.PHONY: test
test: $(OBJDIR)/test/test
	$(OBJDIR)/test/test $(TESTS)
