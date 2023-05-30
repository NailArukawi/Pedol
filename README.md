# Pedol
Elgato Pedal linux support.

## How to build:
grab the latest version of zig: https://github.com/ziglang/zig

then just build this locally

## How to use
when trying to run pedol it needs a config "map.toml"<br />
it needs to be in the same folder as the executable and should contain:
```Toml
# The vendor id for your Elgato Pedal
vendor_id = 0x0fd9

# The product id for your Elgato Pedal
product_id = 0x0086

# The key id for left pedal
left = [54, 36] # Shift + J

# The key id for left pedal
middle = 37 # K

# The key id for left pedal
right = [29, 56, 38] # Ctrl + Alt + L
```

for key ids: https://github.com/torvalds/linux/blob/master/include/uapi/linux/input-event-codes.h

## to note
This program is a bit primative, so expect quirks?
