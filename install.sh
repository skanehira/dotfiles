#!/bin/bash

case $( uname -s ) in
  Linux)  bash install_linux.sh;;
  Darwin) echo Darwin;;
  *)      echo other;;
esac
