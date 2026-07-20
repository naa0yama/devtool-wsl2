#!/usr/bin/env fish

function fish_prompt
	set_color green
	echo -n (prompt_pwd)
	set_color normal
	echo -n '> '
end
