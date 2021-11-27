#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct LyonBuilder LyonBuilder;

typedef struct LyonPoint {
  float x;
  float y;
} LyonPoint;

typedef struct LyonRect {
  float x;
  float y;
  float width;
  float height;
} LyonRect;

typedef struct LyonVertexData {
  const struct LyonPoint *vertex_buf;
  uintptr_t vertex_len;
  const uint16_t *index_buf;
  uintptr_t index_len;
} LyonVertexData;

void lyon_init(void);

void lyon_deinit(void);

struct LyonBuilder *lyon_new_builder(void);

void free_builder(struct LyonBuilder *_b);

void lyon_begin(struct LyonBuilder *b, const struct LyonPoint *pt);

void lyon_line_to(struct LyonBuilder *b, const struct LyonPoint *pt);

void lyon_quadratic_bezier_to(struct LyonBuilder *b,
                              const struct LyonPoint *ctrl_pt,
                              const struct LyonPoint *to_pt);

void lyon_cubic_bezier_to(struct LyonBuilder *b,
                          const struct LyonPoint *ctrl1_pt,
                          const struct LyonPoint *ctrl2_pt,
                          const struct LyonPoint *to_pt);

void lyon_end(struct LyonBuilder *b, bool closed_path);

void lyon_add_rectangle(struct LyonBuilder *b, const struct LyonRect *c_rect);

void lyon_add_polygon(struct LyonBuilder *b,
                      const struct LyonPoint *pts,
                      uintptr_t len,
                      bool closed);

struct LyonVertexData lyon_build_stroke(struct LyonBuilder *b, float line_width);

struct LyonVertexData lyon_build_fill(struct LyonBuilder *b);
