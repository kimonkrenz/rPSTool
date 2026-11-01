// Development-only structural oracle accessor, compiled against pinned headers.
// Handles come from the exported PSTACreateGraph C API, never rPSTool .Call.
#include <pstalgo/graph/AxialGraph.h>
extern "C" int axial_point_group_count(const void* handle)
{
    return static_cast<int>(static_cast<const CAxialGraph*>(handle)->getPointGroupCount());
}
extern "C" unsigned int axial_point_group_size(const void* handle, unsigned int i)
{
    return static_cast<const CAxialGraph*>(handle)->getPointGroupSize(i);
}
extern "C" void axial_point_state(const void* handle, unsigned int i, double* out)
{
    const auto& graph = *static_cast<const CAxialGraph*>(handle);
    const auto& p = graph.getPoint(i);
    const auto world = graph.localToWorld(p.coords);
    out[0] = world.x; out[1] = world.y; out[2] = p.iLine+1;
    out[3] = p.distFromLine; out[4] = p.linePos;
}
