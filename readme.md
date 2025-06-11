# Old, don't use this

I have recently been made aware of a vastly simpler solution to this problem that has been posted on the VDC (https://developer.valvesoftware.com/wiki/Env_projectedtexture#Caveats_and_Fixes). My solution here was so over-engineered that I don't know how I missed it, but the new solution is much, much smaller and has practically zero downsides (Other than the `-tools` mode thing, that still applies, but everything else is irrelevant, it works near flawlessly).

Here is the relevant vscript code. All you need to do is put this into any `env_projectedtexture` that you want to bypass the auto-shutoff:
```Squirrel
function InputTurnOff() {
 	// If the input came from another projected texture, ignore it
 	if (activator && activator.IsValid() && activator.GetClassname() == "env_projectedtexture")
 	 	return false;
 	return true;
}
```

You can even have a separate script to automatically put it into every `env_projectedtexture` for you, just put this into a `logic_script` (changing "path/to/main/script" to the path of the other script):
```Squirrel
local ent = null;
while (ent = Entities.FindByClassname(ent, "env_projectedtexture")) {
 	ent.ValidateScriptScope();
 	DoIncludeScript("path/to/main/script", ent.GetScriptScope());
}
```

The rest of this is here for archival purposes, but I don't recommend using it.


---


# env_multi_projectedtexture

A VScript implementation of multiple active env_projectedtexture entities for Portal 2 (No dll editing or plugins required)

## How it's possible

In the code there is a function called `EnforceSingleProjectionRules`, which forcefully shuts off all projected textures apart from the one that ran the function. Normally it gets called whenever a projected texture activates, however due to an oversight by Valve this function does *not* get called when creating the entity through the `create_flashlight` command or through VScript's `CreateByClassname` function. In both of these cases the newly created `env_projectedtexture` starts active, so we can create as many as we want and they won't turn each other off.

## Usage

### IMPORTANT!

The game MUST be running in `-tools` mode for this to work properly. Without it, the maximum amount of Depth Texture Shadows is limited to 1, which will screw up the shadows cast by the projected textures (tools mode brings this up to 8). If you have the `enableshadows` key disabled on your `env_projectedtexture` this is irrelevant, but for most use cases you probably want it enabled.

There is no possible workaround for this, the engine changes this value by reading the command line parameters directly, and there is no way to modify them through hammer. There also isn't any way to read this value through hammer either, so you can't account for anyone who doesn't have tools mode enabled.

This sucks. I only remembered this after I wrote the entire script, but it greatly reduces the usefulness of it. Since the main use case is for workshop maps (because otherwise you can package an edited dll into your mod), I assume most people playing it won't bother reading the description that tells them run in tools mode (if you even do that in the first place), nor may they even want to do so to begin with.

This is enough of a hack as it is so it's good that it even works at all, but can't win them all I suppose.

---

### Installation

Place the `MultiProj` folder in your VScript directory

### Setup

Set any entity's `vscript` keyvalue to `MultiProj/main.nut`. This can be any entity (except for `env_projectedtexture`), but usually you would use a `logic_script` for this. If you want to delay running the script, send an output to your script entity that runs `runscriptfile "MultiProj/main.nut"`.

And that's it! All `env_projectedtexture` entities in the map will now be modified automatically at runtime to work with the new system.

### Setting Default keyvalues
---

Due to the limitations of VScript, we cannot read the keyvalues of any entities, which includes `env_projectedtexture`. That means any changes you made to the default keyvalues* will not get parsed by the script. This only applies to the starting keyvalues though; Any changes made at runtime (like through inputs) will still work as normal (...mostly, see the "Updating Keyvalues" section for more information)

\* *Note: The default keyvalues in your FGD may not reflect the defaults of the engine*

To get around this, you will have to manually tell the script the keyvalues you want to start off with. There are a couple of methods implemented to achieve this.

### Method 1: Using the `model` keyvalue

This method is the easiest so I recommend it over the others. This also takes precedence over the second method, so if you try to use both only this one will be used

- In your `env_projectedtexture`, turn off `SmartEdit` and add a new keyvalue with a key of `model`
- Set the value to a comma-separated string of all the key-value pairs you want to modify using this format: `key = somevalue, key2 = some value with spaces, ...`
- Keys and values are separated by `=`, and key-value pairs are separated by `,`. Do NOT use quotes, as it will corrupt the VMF

### Method 2: Using the `OnUser1` output

*Note: The OnUser1 output for `env_projectedtexture` entities is reserved by this script and will always be run automatically on initialization, assuming the `model` keyvalue is not present. If you must use this output and you don't have any keyvalues set in `model`, set it to `!!!` instead and the script will not attempt to fire the `OnUser1` output*

This method is more of a hassle, especially under specific circumstances, so I recommend using the first method. Only use this one if you absolutely need to.

- In your `env_projectedtexture`, create a new output that triggers `OnUser1` and set the target to the name of the projected texture that this output is part of. Do NOT use `!self`, you must use the absolute name
- Set the input to be `RunScriptCode` and the parameter override to `setKeyvalues({KEYVALUES});`, where `KEYVALUES` is a list of comma-separated key-value pairs. See below for the format

Unfortunately quoted strings can't be passed through the output, as it would corrupt the VMF, but we need to quote strings for `RunScriptCode` to work properly. To work around this you must send quoted values via these rules:
- If the string is made up of only digits and spaces, pass the value as an array split by the spaces:
    - `"255 255 255 200"` -> `[255, 255, 255, 200]`
- If the value contains any regular characters, pass each character through individually and add them together:
    - `"some string"` -> `'s'+'o'+'m'+'e'+' '+'s'+'t'+'r'+'i'+'n'+'g'`

**Full example:** `OnUser1 some_projtex RunScriptCode setKeyvalues({spawnflags=1,lightcolor=[0,255,0,200]});`

Yes this is very annoying and horrendous (especially that second part), but it's the only way to do it. Luckily most keyvalues you would want to change probably only require the array method, which is easier to deal with.

### Method 3: Hardcode your keyvalues using VScript

If you don't want to use either method your only other option is to edit my script or create your own, and manually hard-code the values you want for every `env_projectedtexture` you use. I don't know why you would want to do that considering the other options are easier, but you can if you need to

### Updating Keyvalues
---

With the way this works, certain keyvalues are reserved by the script to be able to simulate turning the projected texture on and off (because if it actually turned off then it's screwed). The following keyvalues are reserved:

- `lightfov`
- `farz`
- `enableshadows`
- `colortransitiontime` (briefly reserved on script initialization, but is free afterwards)

This shouldn't affect you in most cases, but there is one scenario that it will: If you change one of these keyvalues at runtime while the projected texture is off, then turn it back on again, it will not be saved. To ensure they get saved, you must call the `notifyKVUpdate` script function on that projected texture:

`notifyKVUpdate(key, value, autoSetKV = true)`

Parameters:
- key: The key to update
- value: The value to update it with
- autoSetKV: If it should also update the keyvalue automatically, so you don't also have to send the corresponding output. Set to true by default

## Limitations

This whole thing is pretty jank, mostly due to VScript limitations, but also various small quirks of needing to create `env_projectedtexture`s in this way

- VScript cannot read the keyvalues of entities, so initial keyvalues must be sent in another way as mentioned above. This also means that any keyvalues that don't change through `AddOutput` and don't have a corresponding output can never be changed.
    - The `texturename` keyvalue is one of those. For whatever reason Valve decided to disable the functionality of the `SpotlightTexture` output, and since we cannot set keyvalues when we create the entity that was our only method of changing the keyvalue (AddOutput doesn't work). What this means is that your projected textures will only ever use the `effects/flashlight001` material. I think for general use this is fine, but if you want to do anything fancy then you're out of luck
- Certain keyvalues must be "reserved" to simulate turning on and off, so you must notify the script when these change under certain conditions (as mentioned above). These keyvalues have defaults set by this script that match the engine's defaults, so if your FGD has different defaults you can edit `utils.nut` > `defaultKV` to change them.
- Changing the `pattern` appears to change the pattern for ALL projected textures with "Always Update" enabled, which means you can't have more than 1 moving projected texture with a pattern on screen at a time
- As previously mentioned, there can only be 1 active projected texture at a time, and 8 in `-tools` mode. If the limit is exceeded shadows stop rendering correctly (and it prints `Too many shadow maps this frame!` in the console). At certain angles and positions some shadows will disappear. This means for best results your game should be running in `-tools` mode
- For some reason the default value for `colortransitiontime` causes the projected texture to have a slow startup when initially created. This only matters though if it is active and the player can see it when it spawns. To fix this we have to hijack this value briefly every time we create the entity, which could potentially interfere with user logic
- The OnUser1 output for projected textures is reserved to retrieve keyvalues, and will always be fired at least once by the script. If it is used for something else, this may result in unintended behavior. This technically can be resolved though by only relying on the `model` keyvalue method, but I included both methods anyway just in case. Most likely you would never need to use that output anyway

## Technical Details

Once active, the projected textures must **never** be turned off through normal means (which would be hard to do anyway since the script ensures the base code never runs). If they are, the only way to reactivate them would also trigger `EnforceSingleProjectionRules`. To get past this we must simulate turning them off. There are two ways I came up with to achieve this:
- Hijack a keyvalue to effectively turn it off by making it invisible (through something like `lightcolor` or `lightfov`)
    - Pros:
        - Allows us to create a single new `env_projectedtexture` that replaces the original, saving an edict
        - Anything that targets the original will still target the new one as if it never changed
        - Mostly seamless usage
    - Cons:
        - All outputs attached to the original `env_projectedtexture` are not preserved, and will not transfer to the new one. For most use cases this is likely not a problem, and could be easily worked around through a logic relay (as `env_projectedtexture` has no real outputs)
        - If the projected texture is off and the user wants to change the hijacked keyvalue, they have to manually notify the script that the value changed, such that it can be properly preserved once it turns back on. If the script isn't notified, it will revert the keyvalue back to it's initial state
        - Since we simulate turning off, technically all projected textures in the map are always active at all times, which might cause some problems. From my testing I haven't encountered any real issues from this, and performance seemed to be fine
- Create a new `env_projectedtexture` each time, and destroy it to turn it off
    - Pros:
        - All disabled projected textures are actually disabled, which reduces potential for strange bugs
        - Outputs from the base `env_projectedtexture` are preserved (limited use case though)
    - Cons:
        - The original `env_projectedtexture` must be preserved so that anything that targets it while the new one is "off" doesn't break. This adds a permanent edict
        - Any inputs with parameters sent to the `env_projectedtexture` while it is disabled, or when it becomes disabled, will not be preserved (which is most inputs). VScript can hook into inputs, however there doesn't seem to be a way to retrieve the value associated with it, so any inputs that have a value can't be preserved. The script must manually be notified in that case for *every* input. Alternatively, a workaround is to only ever send inputs when it is active, and to not turn it off until the player has left the area completely, or only turn it off if you want to revert to the original state again once you turn it back on

This script currently only implements the first method since it's better in most ways, but I plan on adding the second method eventually for completeness. If you have any ideas for alternate methods that might work better, feel free to open an issue or pull request