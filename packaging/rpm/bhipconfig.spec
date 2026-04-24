Name:           bhipconfig
Version:        %{version}
Release:        @RELEASE@%{?dist}
Summary:        Futuristic CLI network manager for Linux servers
License:        Proprietary
URL:            https://example.invalid/bhipconfig
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch
Requires:       python3

%description
bhipconfig is an interactive terminal-based network control surface for Linux.
It wraps existing system tooling like iproute2 behind a safer guided UI with
rollback protection for risky network changes.

%prep
%setup -q

%build

%install
install -D -m 0755 bhipconfig %{buildroot}%{_bindir}/bhipconfig
install -D -m 0644 README.md %{buildroot}%{_docdir}/%{name}/README.md

%files
%doc %{_docdir}/%{name}/README.md
%{_bindir}/bhipconfig

%changelog
* Thu Apr 24 2026 Bahari Network Team <packages@bahari.local> - %{version}-@RELEASE@
- Initial package release
