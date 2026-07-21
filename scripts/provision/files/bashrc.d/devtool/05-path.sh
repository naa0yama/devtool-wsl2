#!/usr/bin/env bash

# Add PATH .loca./bin
case ":$PATH:" in
	*":$HOME/.local/bin:"*) ;;
	*) export PATH="$HOME/.local/bin:$PATH" ;;
esac
