#!/bin/bash

ldid -e layout/Applications/nitoUtility.app/nitoUtility > ent.plist
ldid2 -Sent.plist layout/Applications/nitoUtility.app/nitoUtility
rm -rf layout/Applications/nitoUtility.app/_CodeSignature
rm -rf layout/Applications/nitoUtility.app/embedded.mobileprovision

