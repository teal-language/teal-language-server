#!/bin/bash
cd "$(dirname "$0")"
lua teal_language_server/main.lua "$@"
