CXX ?= c++
CXXFLAGS ?= -O2 -Wall -Wextra -Wpedantic
BUILD_DIR ?= build

.PHONY: all check clean memory-probe wpe-probe servo-probe servo-check servo-metrics-check
all: $(BUILD_DIR)/prepare-profile $(BUILD_DIR)/resource-module/libchatgptresources.so

$(BUILD_DIR)/resource-module/libchatgptresources.so: native/resources.cpp native/resource-sample.h
	mkdir -p "$(BUILD_DIR)/resource-module"
	/usr/lib/qt6/moc $$(pkg-config --cflags Qt6Core Qt6Qml) $< -o "$(BUILD_DIR)/resource-module/resources.moc"
	$(CXX) $(CXXFLAGS) -std=c++17 -fPIC -shared -I"$(BUILD_DIR)/resource-module" $< $$(pkg-config --cflags --libs Qt6Core Qt6Qml) -o $@
	printf 'module Slovn.ChatGPTResources\nplugin chatgptresources\n' > "$(BUILD_DIR)/resource-module/qmldir"

$(BUILD_DIR)/prepare-profile: native/prepare-profile.cpp
	mkdir -p "$(BUILD_DIR)"
	$(CXX) $(CXXFLAGS) -std=c++17 $< -o $@

$(BUILD_DIR)/resource-check: tests/resource-check.cpp native/resources.cpp native/resource-sample.h $(BUILD_DIR)/resource-module/libchatgptresources.so
	$(CXX) $(CXXFLAGS) -std=c++17 -fPIC -I"$(BUILD_DIR)/resource-module" $< $$(pkg-config --cflags --libs Qt6Core Qt6Qml) -o $@

wpe-check: wpe-probe $(BUILD_DIR)/wpe-session-check
	QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software timeout 18 /usr/lib/qt6/bin/qmltestrunner -input tests/tst_wpe.qml
	TMPDIR="$(abspath $(BUILD_DIR)/compiler-tmp)" timeout 10 "$(BUILD_DIR)/wpe-session-check"

$(BUILD_DIR)/wpe-session-check: tests/wpe-session-check.cpp native/wpe/WpeSession.h $(BUILD_DIR)/wpe/libchatgptwpe.so
	$(CXX) $(CXXFLAGS) -std=c++17 -fPIC $< "$(BUILD_DIR)/wpe/session-moc.cpp" $$(pkg-config --cflags --libs Qt6Core wpe-webkit-2.0 libsoup-3.0) -o $@

memory-probe: $(BUILD_DIR)/memory-probe

$(BUILD_DIR)/memory-probe: tests/memory-probe.cpp
	mkdir -p "$(BUILD_DIR)"
	$(CXX) $(CXXFLAGS) -std=c++17 -fPIC $< $$(pkg-config --cflags --libs Qt6WebEngineQuick Qt6Quick Qt6Qml Qt6Network) -o $@

servo-probe: $(BUILD_DIR)/servo/libchatgptservo.so $(BUILD_DIR)/servo-metrics/libchatgptservometrics.so

$(BUILD_DIR)/servo-metrics/libchatgptservometrics.so: native/servo/ServoMetrics.cpp native/resource-sample.h
	mkdir -p "$(BUILD_DIR)/servo-metrics"
	/usr/lib/qt6/moc $$(pkg-config --cflags Qt6Core Qt6Qml) $< -o "$(BUILD_DIR)/servo-metrics/ServoMetrics.moc"
	$(CXX) $(CXXFLAGS) -std=c++17 -fPIC -shared -I"$(BUILD_DIR)/servo-metrics" $< $$(pkg-config --cflags --libs Qt6Core Qt6Qml) -o $@
	printf 'module Slovn.ChatGPTServoMetrics\nplugin chatgptservometrics\n' > "$(BUILD_DIR)/servo-metrics/qmldir"

$(BUILD_DIR)/servo-metrics-check: tests/servo-metrics-check.cpp native/servo/ServoMetrics.cpp native/resource-sample.h $(BUILD_DIR)/servo-metrics/libchatgptservometrics.so
	$(CXX) $(CXXFLAGS) -std=c++17 -fPIC -I"$(BUILD_DIR)/servo-metrics" $< $$(pkg-config --cflags --libs Qt6Core Qt6Qml) -o $@

servo-metrics-check: $(BUILD_DIR)/servo-metrics-check
	unit="chatgpt-servo-metrics-test-$$(date +%s)-$$$$"; systemd-run --user --unit="$$unit" --wait --pipe --service-type=exec -p RuntimeMaxSec=5 -p LimitCORE=0 "$(abspath $(BUILD_DIR)/servo-metrics-check)" "$$unit.service"

servo-check: servo-probe $(BUILD_DIR)/servo-transport-check
	timeout 5 "$(BUILD_DIR)/servo-transport-check"

$(BUILD_DIR)/servo-transport-check: tests/servo-transport-check.cpp native/servo/ServoView.cpp $(BUILD_DIR)/servo/libchatgptservo.so
	$(CXX) $(CXXFLAGS) -std=c++17 -fPIC -I"$(BUILD_DIR)/servo" $< $$(pkg-config --cflags --libs Qt6Quick Qt6Qml Qt6Network) -o $@

$(BUILD_DIR)/servo/libchatgptservo.so: native/servo/ServoView.cpp
	mkdir -p "$(BUILD_DIR)/servo"
	/usr/lib/qt6/moc $$(pkg-config --cflags Qt6Quick Qt6Qml Qt6Network) $< -o "$(BUILD_DIR)/servo/ServoView.moc"
	$(CXX) $(CXXFLAGS) -std=c++17 -fPIC -shared -I"$(BUILD_DIR)/servo" $< $$(pkg-config --cflags --libs Qt6Quick Qt6Qml Qt6Network) -o $@
	printf 'module Slovn.ChatGPTServo\nplugin chatgptservo\n' > "$(BUILD_DIR)/servo/qmldir"

wpe-probe: $(BUILD_DIR)/wpe/libchatgptwpe.so $(BUILD_DIR)/wpe/extensions/libprocessidentity.so $(BUILD_DIR)/wpe-memory-probe

$(BUILD_DIR)/wpe/extensions/libprocessidentity.so: native/wpe/process-identity.cpp
	mkdir -p "$(BUILD_DIR)/wpe/extensions"
	$(CXX) $(CXXFLAGS) -std=c++17 -fPIC -shared $< $$(pkg-config --cflags --libs wpe-web-process-extension-2.0) -o $@

$(BUILD_DIR)/wpe/libchatgptwpe.so: native/wpe/WpeView.cpp native/wpe/WpeSession.h native/wpe/WpeRequests.h
	mkdir -p "$(BUILD_DIR)/wpe"
	/usr/lib/qt6/moc $$(pkg-config --cflags Qt6Quick Qt6Qml) $< -o "$(BUILD_DIR)/wpe/WpeView.moc"
	/usr/lib/qt6/moc $$(pkg-config --cflags Qt6Core) native/wpe/WpeSession.h -o "$(BUILD_DIR)/wpe/session-moc.cpp"
	/usr/lib/qt6/moc $$(pkg-config --cflags Qt6Core) native/wpe/WpeRequests.h -o "$(BUILD_DIR)/wpe/requests-moc.cpp"
	$(CXX) $(CXXFLAGS) -std=c++17 -fPIC -shared -I"$(BUILD_DIR)/wpe" -Inative/wpe $< "$(BUILD_DIR)/wpe/session-moc.cpp" "$(BUILD_DIR)/wpe/requests-moc.cpp" $$(pkg-config --cflags --libs Qt6Quick Qt6Qml wpe-webkit-2.0 wpe-platform-2.0 xkbcommon) -o $@
	printf 'module Slovn.ChatGPTWpe\nplugin chatgptwpe\n' > "$(BUILD_DIR)/wpe/qmldir"

$(BUILD_DIR)/wpe-memory-probe: tests/wpe-memory-probe.cpp
	mkdir -p "$(BUILD_DIR)"
	$(CXX) $(CXXFLAGS) -std=c++17 $< $$(pkg-config --cflags --libs wpe-webkit-2.0 wpe-platform-headless-2.0) -o $@

check: all $(BUILD_DIR)/resource-check
	timeout 5 "$(BUILD_DIR)/resource-check"
	node tests/native-checks.mjs "$(abspath $(BUILD_DIR)/prepare-profile)"
	QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software timeout 18 /usr/lib/qt6/bin/qmltestrunner -input tests/tst_native.qml
	omarchy plugin validate .

clean:
	rm -f "$(BUILD_DIR)/prepare-profile" "$(BUILD_DIR)/resource-module/libchatgptresources.so" "$(BUILD_DIR)/resource-module/resources.moc" "$(BUILD_DIR)/resource-module/qmldir"
