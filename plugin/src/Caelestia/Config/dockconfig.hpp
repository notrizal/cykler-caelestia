#pragma once

#include <qstringlist.h>

#include "settings/objectnode.hpp"
#include "common.hpp"
#include "enums.hpp"

namespace caelestia::shell::config {

class DockConfig : public settings::ObjectNode {
    CONFIG_NODE(DockConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_ENUM_PROPERTY(DockVisibility, visibility, DockVisibility::Floating)
    CONFIG_ENUM_PROPERTY(DockHoverEffect, hoverEffect, DockHoverEffect::Magnification)
    CONFIG_PROPERTY(int, iconSize, 42)
    CONFIG_PROPERTY(int, previewDelay, 160)
    CONFIG_PROPERTY(int, hideDelay, 350)
    CONFIG_PROPERTY(bool, perMonitorWindows, false)
    CONFIG_GLOBAL_PROPERTY(QStringList, pinnedApps, {})
    CONFIG_GLOBAL_PROPERTY(QStringList, excludedScreens, {})
};

} // namespace caelestia::shell::config
