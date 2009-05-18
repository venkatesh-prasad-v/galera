#include "gcomm/time.hpp"

BEGIN_GCOMM_NAMESPACE

/*
 * Static member initialization
 */
const time_t Time::MicroSecond = time_t(1);
const time_t Time::MilliSecond = time_t(1000)*MicroSecond;
const time_t Time::Second = time_t(1000)*MilliSecond;

END_GCOMM_NAMESPACE
