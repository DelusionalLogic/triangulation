CC ?= gcc

OBJDIR ?= obj
SRCDIR ?= src

PACKAGES = libdeflate
LIBS =
INCS = -Isrc/
CFG = -std=gnu11 -fms-extensions -flto
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

LIBS += $(shell pkg-config --libs $(PACKAGES))
INCS += $(shell pkg-config --cflags $(PACKAGES))

.DEFAULT_GOAL := index

src/.clang_complete: Makefile
	@(for i in $(filter-out -O% -DNDEBUG, $(CFG) $(CPPFLAGS) $(CFLAGS) $(INCS)); do echo "$$i"; done) > $@

index: $(OBJS_C)
	$(CC) $(CFG) $(CPPFLAGS) $(LDFLAGS) $(CFLAGS) -o $@ $(OBJS_C) $(LIBS)

$(OBJDIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFG) $(CPPFLAGS) $(CFLAGS) $(INCS) -MMD -o $@ -c $<
