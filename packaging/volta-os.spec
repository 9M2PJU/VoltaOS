Name:           volta-os
Version:        1.0
Release:        1%{?dist}
Summary:        Volta OS - in-car touchscreen interface for Linux (Qt6/QML)
License:        GPL-3.0-only
URL:            https://github.com/Omardigio/VoltaOS
Source0:        https://github.com/Omardigio/VoltaOS/archive/refs/tags/v%{version}.tar.gz

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  pkg-config
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  qt6-qtquick3d-devel
BuildRequires:  qt6-qtwebengine-devel
BuildRequires:  qt6-qtmultimedia-devel
BuildRequires:  qt6-qtwebsockets-devel
BuildRequires:  qt6-qtpositioning-devel
BuildRequires:  qt6-qtlocation-devel
BuildRequires:  qt6-qtvirtualkeyboard-devel
BuildRequires:  qt6-qtwayland-devel
BuildRequires:  libusb1-devel
BuildRequires:  ffmpeg-devel
BuildRequires:  wayland-protocols-devel
BuildRequires:  libX11-devel

Requires:       mpv
Requires:       python3
Requires:       python3-dbus
Requires:       NetworkManager
Requires:       bluez
Requires:       pipewire-pulseaudio
Suggests:       spotifyd
Suggests:       easyeffects
Suggests:       gamescope

%description
Volta OS is a full-screen in-car infotainment interface for Linux,
written in Qt 6 / QML. Map, music, phone, CarPlay, video and games in one
touchscreen UI; it also acts as a Wayland compositor so native apps open
inside the UI. Python service deps (ytmusicapi, spotipy, ...): see
%{_datadir}/volta_os and docs/installation.md.

%prep
%autosetup -n VoltaOS-%{version}

%build
%cmake -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
%cmake_install

%files
%{_bindir}/VoltaOS
%{_datadir}/volta_os/
%{_datadir}/applications/volta-os.desktop
%{_datadir}/pixmaps/volta-os.png

%changelog
* Tue Nov 10 2026 VoltaOS contributors - 1.0-1
- Initial RPM packaging (CPack + spec for COPR/rpmbuild)
