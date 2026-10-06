"""Classify original-site visual evidence; never grant capture permission."""
import json
import sys


def accepts(metadata, surface):
    if metadata.get('captureKind') != 'current-browser-item':
        return False
    if metadata.get('pageKind') != 'account-capable-live-page':
        return False
    if metadata.get('imageInspected') is not True:
        return False
    if surface == 'primary-pixels':
        return metadata.get('target') == 'primary-browser'
    # This tool has no auxiliary/chrome/input capability. A fixture is not fallback.
    return False


def self_check():
    live = {'captureKind': 'current-browser-item', 'pageKind': 'account-capable-live-page',
            'imageInspected': True, 'target': 'primary-browser'}
    assert accepts(live, 'primary-pixels')
    assert not accepts(dict(live, captureKind='reviewed-qml-fixture'), 'primary-pixels')
    assert not accepts(dict(live, pageKind='inert-fixture'), 'primary-pixels')
    assert not accepts(dict(live, imageInspected=False), 'primary-pixels')
    for surface in ['auxiliary-pixels', 'native-chrome', 'menu-interaction']:
        assert not accepts(live, surface)


if __name__ == '__main__':
    self_check()
    if len(sys.argv) == 3:
        with open(sys.argv[1]) as file:
            admitted = accepts(json.load(file), sys.argv[2])
        print('PASS scoped live evidence' if admitted else 'NOT VERIFIED for requested live surface')
        sys.exit(0 if admitted else 1)
    print('PASS live/fixture and surface-scope regressions; not model obedience')
