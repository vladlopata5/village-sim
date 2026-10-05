extends RefCounted
## Injected RNG: options and their weights stay separate from need priorities.
static func pick(options: Array, rng: RandomNumberGenerator):
	var total := 0.0
	for option in options: total += maxf(0.0, option.option_weight)
	if total <= 0: return null
	var draw := rng.randf() * total
	for option in options:
		draw -= maxf(0.0, option.option_weight)
		if draw < 0: return option
	return options.back()
