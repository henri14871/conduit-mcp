--!strict

return table.freeze({
	colors = table.freeze({
		bg = Color3.fromRGB(20, 20, 20),
		surface = Color3.fromRGB(30, 30, 30),
		border = Color3.fromRGB(60, 60, 60),
		text = Color3.fromRGB(220, 220, 220),
		textMuted = Color3.fromRGB(120, 120, 120),
		accent = Color3.fromRGB(220, 40, 40),
		accentMuted = Color3.fromRGB(140, 30, 30),
		green = Color3.fromRGB(0, 200, 83),
		yellow = Color3.fromRGB(255, 193, 7),
		red = Color3.fromRGB(244, 67, 54),
		logBg = Color3.fromRGB(18, 18, 18),
		btnHover = Color3.fromRGB(45, 45, 45),
	}),

	spacing = table.freeze({
		xs = 2,
		sm = 4,
		md = 8,
		lg = 12,
		xl = 16,
	}),

	stroke = table.freeze({
		thin = 1,
		bold = 2,
	}),

	font = table.freeze({
		heading = Enum.Font.GothamBold,
		body = Enum.Font.GothamMedium,
		mono = Enum.Font.Code,
		label = Enum.Font.Gotham,
	}),

	textSize = table.freeze({
		xs = 10,
		sm = 11,
		md = 12,
		lg = 14,
		xl = 18,
	}),

	MAX_LOG_ENTRIES = 50,
})
