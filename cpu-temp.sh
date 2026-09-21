#!/bin/bash
sensors 2>&1 | grep -A5 legion_hwmon 
