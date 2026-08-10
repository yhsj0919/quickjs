#include <gtest/gtest.h>

#include "quickjs_plugin.h"

namespace quickjs {
namespace test {

TEST(QuickjsPlugin, CanConstruct) {
  QuickjsPlugin plugin;
  SUCCEED();
}

}  // namespace test
}  // namespace quickjs
