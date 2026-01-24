# Rules

* Shell scripts must have a shebang in the format `/usr/bin/env <SHELL>`
* When making corrections, run the code through syntax check and linter.
* Use tabs for indentation
* Avoid abbreviating command options
* In fish shell, commands are resolved in the order Function > Builtin > External command, so if you want to call a Builtin command, you must declare it explicitly.
* When defining variables, enclose them in double/single quotes to make argument expansion safer.
