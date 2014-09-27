# This is the common makefile used to build all top-level modules
# It contains common recipes for bulding C/CPP/asm files to objects, and
# to combine those objects into libraries or elf files.

MAKEOVERRIDES:=$(filter-out TARGET%,$(MAKEOVERRIDES))

# silence commands by default

ifdef v
ECHO=echo
VERBOSE=
else
ECHO = #
VERBOSE=@
MAKE_ARGS:=$(MAKE_ARGS) -s
endif

echo=$(ECHO $1)

# Recursive wildcard function - finds matching files in a directory tree
rwildcard = $(wildcard $1$2) $(foreach d,$(wildcard $1*),$(call rwildcard,$d/,$2))
target_files = $(patsubst $(MODULE_PATH)/%,%,$(call rwildcard,$(MODULE_PATH)/$1,$2))

# import this modules symbols
include $(MODULE_PATH)/import.mk

include $(call rwildcard,$(MODULE_PATH)/,build.mk)

# pull in the include.mk files from each dependency, and make them relative to
# the dependency module directory
DEPS_INCLUDE_SCRIPTS =$(foreach module,$(DEPENDENCIES),../$(module)/import.mk)
include $(DEPS_INCLUDE_SCRIPTS)	

# create a list of targets to clean from the list of dependencies
CLEAN_DEPENDENCIES=$(patsubst %,clean_%,$(MAKE_DEPENDENCIES))
	
ifeq ("$(DEBUG_BUILD)","y") 
CFLAGS += -DDEBUG_BUILD
else
CFLAGS += -DRELEASE_BUILD
endif

# add include directories
CFLAGS += $(patsubst %,-I%,$(INCLUDE_DIRS)) -I.
# Generate dependency files automatically.
CFLAGS += -MD -MP -MF $@.d
CFLAGS += -ffunction-sections -Wall -Werror -Wno-switch -fmessage-length=0
CFLAGS += -DSPARK=1

LDFLAGS += $(patsubst %,-L%,$(LIB_DIRS))
LDFLAGS += $(patsubst %,-l%,$(LIBS))

# Assembler flags
ASFLAGS += -x assembler-with-cpp -fmessage-length=0

# Collect all object and dep files
ALLOBJ += $(addprefix $(BUILD_PATH)/, $(CSRC:.c=.o))
ALLOBJ += $(addprefix $(BUILD_PATH)/, $(CPPSRC:.cpp=.o))
ALLOBJ += $(addprefix $(BUILD_PATH)/, $(ASRC:.S=.o))

ALLDEPS += $(addprefix $(BUILD_PATH)/, $(CSRC:.c=.o.d))
ALLDEPS += $(addprefix $(BUILD_PATH)/, $(CPPSRC:.cpp=.o.d))
ALLDEPS += $(addprefix $(BUILD_PATH)/, $(ASRC:.S=.o.d))

ifeq ("$(TARGET_TYPE)","a") 
TARGET_FILE_PREFIX = lib
endif

ifneq ("$(TARGET_DIR)","")
TARGET_DIR := $(TARGET_DIR)/
endif

TARGET_FILE ?= $(MODULE)
TARGET_BASE ?= $(BUILD_PATH)/$(TARGET_DIR)$(TARGET_FILE_PREFIX)$(TARGET_FILE)
TARGET ?= $(TARGET_BASE).$(TARGET_TYPE)

# All Target
all: $(MAKE_DEPENDENCIES) $(TARGET)

elf: $(TARGET_BASE).elf
bin: $(TARGET_BASE).bin
hex: $(TARGET_BASE).hex
lst: $(TARGET_BASE).lst

# Program the core using dfu-util. The core should have been placed
# in bootloader mode before invoking 'make program-dfu'
program-dfu: $(TARGET_BASE).bin
	@echo Flashing using dfu:
	$(DFU) -d 1d50:607f -a 0 -s 0x08005000:leave -D $<

# Program the core using the cloud. SPARK_CORE_ID and SPARK_ACCESS_TOKEN must
# have been defined in the environment before invoking 'make program-cloud'
program-cloud: $(TARGET_BASE).bin
	@echo Flashing using cloud API, CORE_ID=$(SPARK_CORE_ID):
	$(CURL) -X PUT -F file=@$< -F file_type=binary $(CLOUD_FLASH_URL)

# Display size
size: $(TARGET_BASE).elf
	$(call,echo,'Invoking: ARM GNU Print Size')
	$(VERBOSE)$(SIZE) --format=berkeley $<
	$(call,echo,)

# create a object listing from the elf file
%.lst: %.elf
	$(call,echo,'Invoking: ARM GNU Create Listing')
	$(VERBOSE)$(OBJDUMP) -h -S $< > $@
	$(call,echo,'Finished building: $@')
	$(call,echo,)

# Create a hex file from ELF file
%.hex : %.elf
	$(call,echo,'Invoking: ARM GNU Create Flash Image')
	$(VERBOSE)$(OBJCOPY) -O ihex $< $@
	$(call,echo,)

# Create a bin file from ELF file
%.bin : %.elf
	$(call,echo,'Invoking: ARM GNU Create Flash Image')
	$(VERBOSE)$(OBJCOPY) -O binary $< $@
	$(call,echo,)

$(TARGET_BASE).elf : $(ALLOBJ)
	$(call,echo,'Building target: $@')
	$(call,echo,'Invoking: ARM GCC C++ Linker')
	$(VERBOSE)$(MKDIR) $(dir $@)
	$(VERBOSE)$(CPP) $(CFLAGS) $(ALLOBJ) --output $@ $(LDFLAGS)
	$(call,echo,)

# Tool invocations
$(TARGET_BASE).a : $(ALLOBJ)	
	$(call,echo,'Building target: $@')
	$(call,echo,'Invoking: ARM GCC Archiver')
	$(VERBOSE)$(MKDIR) $(dir $@)
	$(VERBOSE)$(AR) -cr $@ $^
	$(call,echo,)

# C compiler to build .o from .c in $(BUILD_DIR)
$(BUILD_PATH)/%.o : $(MODULE_PATH)/%.c
	$(call,echo,'Building file: $<')
	$(call,echo,'Invoking: ARM GCC C Compiler')
	$(VERBOSE)$(MKDIR) $(dir $@)
	$(VERBOSE)$(CC) $(CFLAGS) -c -o $@ $<
	$(call,echo,)

# Assember to build .o from .S in $(BUILD_DIR)
$(BUILD_PATH)/%.o : $(MODULE_PATH)/%.S
	$(call,echo,'Building file: $<')
	$(call,echo,'Invoking: ARM GCC Assembler')
	$(VERBOSE)$(MKDIR) $(dir $@)
	$(VERBOSE)$(CC) $(ASFLAGS) -c -o $@ $<
	$(call,echo,)
	
# CPP compiler to build .o from .cpp in $(BUILD_DIR)
# Note: Calls standard $(CC) - gcc will invoke g++ as appropriate
$(BUILD_PATH)/%.o : $(MODULE_PATH)/%.cpp
	$(call,echo,'Building file: $<')
	$(call,echo,'Invoking: ARM GCC CPP Compiler')
	$(VERBOSE)$(MKDIR) $(dir $@)
	$(VERBOSE)$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $@ $<
	$(call,echo,)

# Other Targets
clean: clean_deps
	$(VERBOSE)$(RM) $(ALLOBJ) $(ALLDEPS) $(TARGET)
	$(VERBOSE)$(RMDIR) $(BUILD_PATH)
	$(call,echo,)

# allow recursive invocation across dependencies to make
clean_deps: $(CLEAN_DEPENDENCIES)
make_deps: $(MAKE_DEPENDENCIES)
	
$(MAKE_DEPENDENCIES):
	$(VERBOSE)$(MAKE) -C ../$@ $(SUBDIR_GOALS) $(MAKE_ARGS)

$(CLEAN_DEPENDENCIES):
	$(VERBOSE)$(MAKE) -C ../$(patsubst clean_%,%,$@) clean $(MAKE_ARGS)


.PHONY: all clean elf bin hex size program-dfu program-cloud make_deps clean_deps $(MAKE_DEPENDENCIES) $(CLEAN_DEPENDENCIES)
.SECONDARY:

# Include auto generated dependency files
ifneq ("MAKECMDGOALS","clean")
-include $(ALLDEPS)
endif


