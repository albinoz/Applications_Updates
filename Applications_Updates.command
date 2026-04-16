#!/bin/bash
clear

# Purge /tmp/com.adam.Full_Update/
rm -fr /tmp/com.adam.Full_Update/

Uptime=$(system_profiler SPSoftwareDataType | grep "Time since boot:" | cut -d ':' -f2 | cut -d ' ' -f2-9)
OSX=$(sw_vers -productVersion)
OSXMajor=$(sw_vers -productVersion | cut -d'.' -f1)
if [[ "$OSXMajor" -ge 11 ]]; then OSXV=$(echo "$OSXMajor"+5 | bc) ; else OSXV=$(sw_vers -productVersion | cut -d'.' -f2) ; fi
LANG=$(defaults read -g AppleLocale | cut -d'_' -f1)
User=$(whoami)
UUID=$(dscl . -read /Users/"$User" | grep GeneratedUID | cut -d' ' -f2)
dPass=$(echo "$User"'*'"$UUID")
dSalt=$(echo "$dPass" | sed "s@[^0-9]@@g")
tput bold ; echo "adam | 2026-02-25" ; tput sgr0
tput bold ; echo "Applications Updates" ; tput sgr0
tput bold ; echo "mac OS | 10.15 < 15" ; tput sgr0

# Check Minimum System
if [ "$OSXV" -ge 12 ] ; then echo System "$OSX" Supported > /dev/null ; else echo System "$OSX" not Supported && exit ; fi

echo; date
echo "$(hostname -s)" - "$(whoami)" - "$(sw_vers -productVersion)" - "$LANG"
#fdesetup status
echo "Uptime:" "$Uptime"

# Check Crypt Install ( admin Password )
if ls ~/Library/Preferences/com.adam.Crypt.plist > /dev/null ; then
	echo ; echo '✅ ' Admin Crypt AllReady Installed
	Pass=`cat ~/Library/Preferences/com.adam.Crypt.plist | sed -n 6p | cut -d'>' -f2 | cut -d'<' -f1`
	AdminPass=`echo $Pass | openssl aes-256-cbc -a -d -pass pass:$dPass -iv $dSalt`
		if echo $AdminPass | sudo -S -k echo '🔒 ' Test KeyPass ; then
			echo '🔓 ' Good Password - You Shall Pass
		else
			echo '🔒 ' Wrong Password - You Shall Not Pass !
			rm -vfr ~/Library/Preferences/com.adam.Crypt.plist
			exit
		fi
else
	while  :
	do
		echo '🔄 ' Admin Crypt Install
		echo -n 'Password : ' && read -s password

			if echo $password | sudo -S -k echo '🔓 ' Good Password - You Shall Pass ; then
				AdminPass=`echo $password | openssl aes-256-cbc -a -pass pass:$dPass -iv $dSalt`
				/usr/libexec/PlistBuddy -c "add Crypt_Pass string $AdminPass" ~/Library/Preferences/com.adam.Crypt.plist
				Pass=`cat ~/Library/Preferences/com.adam.Crypt.plist | sed -n 6p | cut -d'>' -f2 | cut -d'<' -f1`
				AdminPass=`echo $Pass | openssl aes-256-cbc -a -d -pass pass:$dPass -iv $dSalt`
				break
			else
				echo '🔒 ' Wrong Password - You Shall Not Pass !
			fi
	done
fi

# Check Homebrew Install
tput bold ; echo ; echo '♻️ ' Check Homebrew Install ; tput sgr0 ; sleep 1
if ls /*/*/bin/ | grep brew > /dev/null ; then tput sgr0 ; echo "HomeBrew AllReady Installed" ; else tput bold ; echo "Installing HomeBrew" ; tput sgr0 ; /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)" ; fi

# Check Homebrew Minimum && Updates
tput bold ; echo ; echo '♻️ '  "Check Homebrew Updates & Minimum" ; tput sgr0 ; sleep 1
brew update ; brew upgrade --formula ; brew cleanup -s ; brew autoremove ; rm -rf "$(brew --cache)"
if brew tap | grep "buo/cask-upgrade" > /dev/null ; then echo '✅ '"brew-cask-upgrade Already Installed"; else brew tap buo/cask-upgrade ; fi
if which mas | grep /*/local/bin/mas > /dev/null ; then echo '✅ '"mas Already Installed" ; else brew install mas ; fi

# Export mas MAS_NO_AUTO_INDEX=1
#[[ -f ~/.zprofile ]] && profile=~/.zprofile || profile=~/.profile
#grep -q 'MAS_NO_AUTO_INDEX=1' "$profile" || echo 'export MAS_NO_AUTO_INDEX=1' >> "$profile"

################### Patch OpenCore copy-xattrs.swift Start

# Detect OpenCore Legacy Patcher & patch copy-xattrs.swift si nécessaire
tput bold ; echo ; echo '♻️ ' Check OpenCore Legacy Patcher ; tput sgr0 ; sleep 1
XATTRS_SWIFT="/usr/local/Homebrew/Library/Homebrew/cask/utils/copy-xattrs.swift"

if nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version > /dev/null 2>&1 ; then
    echo '✅ ' OpenCore Detected

    if [ -f "$XATTRS_SWIFT" ] ; then
        # Backup original si pas déjà fait
        if [ ! -f "${XATTRS_SWIFT}.orig" ] ; then
            echo $AdminPass | sudo -S cp "$XATTRS_SWIFT" "${XATTRS_SWIFT}.orig"
            echo '✅ ' Backup copy-xattrs.swift.orig Created
        else
            echo '✅ ' Backup copy-xattrs.swift.orig Already Exists
        fi

        # Vérifier si le patch est déjà appliqué
        if grep -q "errno == 2" "$XATTRS_SWIFT" ; then
            echo '✅ ' copy-xattrs.swift Already Patched
        else
            echo '🔄 ' Patching copy-xattrs.swift...
            echo $AdminPass | sudo -S tee "$XATTRS_SWIFT" > /dev/null << 'SWIFT_PATCH'
#!/usr/bin/swift

import Foundation

struct SwiftErr: TextOutputStream {
    public static var stream = SwiftErr()

    mutating func write(_ string: String) {
        fputs(string, stderr)
    }
}

guard CommandLine.arguments.count >= 3 else {
    print("Usage: swift copy-xattrs.swift <source> <dest>")
    exit(2)
}

CommandLine.arguments[2].withCString { destinationPath in
    let destinationNamesLength = listxattr(destinationPath, nil, 0, 0)
    if destinationNamesLength == -1 {
        // errno 2 = ENOENT : destination absente (OpenCore Legacy), skip silencieux
        if errno == 2 {
            exit(0)
        }
        print("listxattr for destination failed: \(errno)", to: &SwiftErr.stream)
        exit(1)
    }
    let destinationNamesBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: destinationNamesLength)
    if listxattr(destinationPath, destinationNamesBuffer, destinationNamesLength, 0) != destinationNamesLength {
        print("Attributes changed during system call", to: &SwiftErr.stream)
        exit(1)
    }

    var destinationNamesIndex = 0
    while destinationNamesIndex < destinationNamesLength {
        let attribute = destinationNamesBuffer + destinationNamesIndex

        if removexattr(destinationPath, attribute, 0) != 0 {
            print("removexattr for \(String(cString: attribute)) failed: \(errno)", to: &SwiftErr.stream)
            exit(1)
        }

        destinationNamesIndex += strlen(attribute) + 1
    }
    destinationNamesBuffer.deallocate()

    CommandLine.arguments[1].withCString { sourcePath in
        let sourceNamesLength = listxattr(sourcePath, nil, 0, 0)
        if sourceNamesLength == -1 {
            print("listxattr for source failed: \(errno)", to: &SwiftErr.stream)
            exit(1)
        }
        let sourceNamesBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: sourceNamesLength)
        if listxattr(sourcePath, sourceNamesBuffer, sourceNamesLength, 0) != sourceNamesLength {
            print("Attributes changed during system call", to: &SwiftErr.stream)
            exit(1)
        }

        var sourceNamesIndex = 0
        while sourceNamesIndex < sourceNamesLength {
            let attribute = sourceNamesBuffer + sourceNamesIndex

            let valueLength = getxattr(sourcePath, attribute, nil, 0, 0, 0)
            if valueLength == -1 {
                print("getxattr for \(String(cString: attribute)) failed: \(errno)", to: &SwiftErr.stream)
                exit(1)
            }
            let valueBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: valueLength)
            if getxattr(sourcePath, attribute, valueBuffer, valueLength, 0, 0) != valueLength {
                print("Attributes changed during system call", to: &SwiftErr.stream)
                exit(1)
            }

            if setxattr(destinationPath, attribute, valueBuffer, valueLength, 0, 0) != 0 {
                print("setxattr for \(String(cString: attribute)) failed: \(errno)", to: &SwiftErr.stream)
                exit(1)
            }

            valueBuffer.deallocate()
            sourceNamesIndex += strlen(attribute) + 1
        }
        sourceNamesBuffer.deallocate()
    }
}
SWIFT_PATCH
            echo '✅ ' copy-xattrs.swift Patched OK
        fi
    fi
else
    echo '✅ ' OpenCore Not Detected - No Patch Needed
fi

################### Patch OpenCore copy-xattrs.swift End

# Check AppleStore Updates
tput bold ; echo ; echo '♻️ ' Check AppleStore Updates ; tput sgr0 ; sleep 1
if which mas | grep /*/local/bin/mas > /dev/null ; then MAS_NO_AUTO_INDEX=1 mas list | awk '{print $2 " " $3 " " $4 " " $5 " " $6}';  MAS_NO_AUTO_INDEX=1 mas upgrade ; else brew install mas ; fi


################### Force Install Brew Formula for Apps Found Start

#-> Brew Cask & Apple Store Compare to /Applications Installed
# Check Installed / Linked Cask Apps
tput bold ; echo ; echo '♻️ ' Check Installed / Linked Cask Apps ; tput sgr0 ; sleep 1

# Create /tmp/com.adam.Full_Update/ Folder
mkdir /tmp/com.adam.Full_Update/

# List /Applications Installed (normalisation accents + nettoyage)
find /Applications -maxdepth 1 -iname "*.app" \
  | cut -d'/' -f3 \
  | sed 's/\.app$//g' \
  | sed 's/ /-/g' \
  | tr 'A-Z' 'a-z' \
  | sed 's/é/e/g; s/è/e/g; s/ê/e/g; s/ë/e/g' \
  | sed 's/à/a/g; s/â/a/g; s/ä/a/g' \
  | sed 's/ù/u/g; s/û/u/g; s/ü/u/g' \
  | sed 's/î/i/g; s/ï/i/g' \
  | sed 's/ô/o/g; s/ö/o/g' \
  | sed 's/ç/c/g' \
  | sed 's/[^a-z0-9-]//g' \
  | sed 's/-*$//g' \
  | sort -u > /tmp/com.adam.Full_Update/App.txt

# List AppleStore Apps Installed
MAS_NO_AUTO_INDEX=1 mas list | cut -d'(' -f1 | sed s'/.$//' | cut -d' ' -f2-3 | sed 's/ /-/g'| tr 'A-Z ' 'a-z ' > /tmp/com.adam.Full_Update/mas.txt

# List Cask Apps Availaibles (via API JSON Homebrew)
curl -s https://formulae.brew.sh/api/cask.json \
  | /usr/bin/python3 -c "
import sys, json
data = json.load(sys.stdin)
for c in data:
    print(c['token'])
" | sort > /tmp/com.adam.Full_Update/cask.txt

# Merge Only Installed /Applications from Cask List
awk 'NR==FNR{arr[$0];next} $0 in arr' /tmp/com.adam.Full_Update/cask.txt /tmp/com.adam.Full_Update/App.txt > /tmp/com.adam.Full_Update/Installed.txt

# Remove Cask Apps AllReady Installed from AppleStore
awk 'NR==FNR{a[$0];next} !($0 in a)' /tmp/com.adam.Full_Update/mas.txt /tmp/com.adam.Full_Update/Installed.txt > /tmp/com.adam.Full_Update/nomas-Installed.txt

# Remove Cask Apps AllReady Installed and Linked
brew list --cask | tr -d " " > /tmp/com.adam.Full_Update/cask-installed.txt
if wc -l < /private/tmp/com.adam.Full_Update/cask-installed.txt | tr -d ' ' | grep -w 0 >/dev/null
# If not cask installed
then echo First Search For Applications Sync to Casks ; sleep 1
cat /tmp/com.adam.Full_Update/nomas-Installed.txt > /tmp/com.adam.Full_Update/Final-List.txt
# If at less one cask Installed
else echo Search For News Applications Sync to Casks ; sleep 1
awk 'NR==FNR{a[$0];next} !($0 in a)' /tmp/com.adam.Full_Update/cask-installed.txt /tmp/com.adam.Full_Update/nomas-Installed.txt > /tmp/com.adam.Full_Update/Final-List.txt
fi

# Force Reinstall Cask Apps without Link Found By LANG Used
sed "s/^/brew reinstall --cask --force --adopt --language=$LANG /" /private/tmp/com.adam.Full_Update/Final-List.txt > /tmp/com.adam.Full_Update/InstallNow.command
chmod 755 /private/tmp/com.adam.Full_Update/InstallNow.command && /private/tmp/com.adam.Full_Update/InstallNow.command

################### Force Install Brew Formula for Apps Found End


# Apps Updates ( no lastest )
tput bold ; echo ; echo '♻️ '  Check Apps Updates ; tput sgr0 ; sleep 2
brew cu --all --yes --force --no-brew-update

rm -fr /tmp/com.adam.Full_Update/

# Time
echo ; echo '✅ ' All Updates Completed ; tput sgr0
printf '%dh:%dm:%ds\n' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60))
