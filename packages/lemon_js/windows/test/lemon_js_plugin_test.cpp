#include <gtest/gtest.h>

#include "lemon_js_plugin.h"

namespace lemon_js {
namespace test {

TEST(LemonJsPlugin, CanConstruct) {
  LemonJsPlugin plugin;
  SUCCEED();
}

}  // namespace test
}  // namespace lemon_js
