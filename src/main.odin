package raytr

import        "core:os"
import        "core:fmt"
import        "core:math"
import img    "core:image"
import        "core:image/bmp"
import linalg "core:math/linalg/glsl"
import rl     "vendor:raylib"

vec2  :: [2]f32
vec3  :: [3]f32
ivec2 :: [2]i32

ray_t :: struct
{
  pos : vec3,
  dir : vec3,
}
hit_t :: struct
{
  pos    : vec3,
  normal : vec3,
  dist   : f32,
  front_face : bool,
}

camera_t :: struct
{
  center : vec3,
  focal_length : f32,
}

Obj_Type :: enum
{
  Sphere,
}
obj_t :: struct
{
  type: Obj_Type,
  pos : vec3,

  radius : f32,
}
obj_arr : [dynamic]obj_t

NEAR_PLANE :: 0.01
FAR_PLANE  :: 1000

main :: proc()
{
  // width     := 1920
  // height    := 1080
  // w_h_ratio := f32(height) / f32(width)

  aspect_ratio : f32 = 16.0 / 9.0
  image_width  := 1920
  
  // Calculate the image height, and ensure that it's at least 1.
  image_height := int(f32(image_width) / aspect_ratio)
  image_height  = (image_height < 1) ? 1 : image_height
  
  // Viewport widths less than one are ok since they are real valued.
  viewport_height : f32 = 2.0
  viewport_width  := viewport_height * (f32(image_width) / f32(image_height));

  cam := camera_t{ center=vec3{0,0,0}, focal_length=1.0 }
    
  // Calculate the vectors across the horizontal and down the vertical viewport edges.
  viewport_u := vec3{ viewport_width, 0, 0 }
  viewport_v := vec3{ 0, -viewport_height, 0 }

  // Calculate the horizontal and vertical delta vectors from pixel to pixel.
  pixel_delta_u := viewport_u / f32(image_width)
  pixel_delta_v := viewport_v / f32(image_height)

  // Calculate the location of the upper left pixel.
  viewport_upper_left := cam.center - vec3{ 0, 0, cam.focal_length} - viewport_u/2 - viewport_v/2
  pixel00_loc := viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v);

  buffer := make( []img.RGBA_Pixel, image_width * image_height )


  append( &obj_arr, obj_t{ pos=vec3{ 0, 0, -1 }, radius=0.5 } )
  append( &obj_arr, obj_t{ pos=vec3{ 3, 1, -3 }, radius=0.5 } )

  for j := 0; j < image_height; j += 1 
  {
    for i := 0; i < image_width; i += 1
    {
      pixel_center  := pixel00_loc + (f32(i) * pixel_delta_u) + (f32(j) * pixel_delta_v)
      ray_direction := pixel_center - cam.center
      r := ray_t{ pos=cam.center, dir=ray_direction }

      pixel_color : vec3
      closest_hit : hit_t
      closest_hit.dist = 10000000
      for obj in obj_arr
      { 
        color, hit := ray_color( r, obj )
        if hit.dist < closest_hit.dist
        {
          pixel_color = color
          closest_hit = hit
        }
      }
      
      buffer[ j*image_width + i ].x = u8( clamp( 0, 255, pixel_color.x * 255 ) )
      buffer[ j*image_width + i ].y = u8( clamp( 0, 255, pixel_color.y * 255 ) )
      buffer[ j*image_width + i ].z = u8( clamp( 0, 255, pixel_color.z * 255 ) )
    }
  }

  res, ok := img.pixels_to_image( buffer, image_width, image_height ) 
  assert( ok )

  bmp.save_to_file( "test.bmp", &res )

}

ray_at :: proc( ray: ray_t, t : f32 ) -> vec3 
{
  return ray.pos + t * ray.dir
}
ray_color :: proc( ray: ray_t, obj: obj_t ) -> ( col: vec3, hit: hit_t )
{
  // vec3{ 0,0,-1 }, 0.5
  has_hit, hit_info := hit_sphere( obj, ray, NEAR_PLANE, FAR_PLANE )
  if has_hit 
  {
    N := linalg.normalize( ray_at( ray, hit_info.dist ) - vec3{ 0, 0, -1 } )
    return 0.5 * vec3{ N.x+1, N.y+1, N.z+1 }, hit_info
  }
  hit_info.dist = 1000000

  unit_direction := linalg.normalize( ray.dir )
  a := 0.5 * ( unit_direction.y + 1.0 )
  return linalg.lerp_vec3( vec3{ 1.0, 1.0, 1.0 }, { 0.5, 0.7, 1.0 }, a ), hit_info
}

hit_sphere :: proc( sphere: obj_t, ray: ray_t, ray_tmin, ray_tmax: f32 ) -> ( hit: bool, rec: hit_t )
{
  oc := sphere.pos - ray.pos
  a := linalg.length( ray.dir ) * linalg.length( ray.dir )
  h := linalg.dot( ray.dir, oc )
  c := linalg.length( oc ) * linalg.length( oc ) - sphere.radius * sphere.radius

  discriminant : f32 = h*h - a*c
  if discriminant < 0 do return false, rec

  sqrtd := math.sqrt( discriminant )

  // Find the nearest root that lies in the acceptable range.
  root := (h - sqrtd) / a
  if root <= ray_tmin || ray_tmax <= root 
  {
      root = (h + sqrtd) / a
      if root <= ray_tmin || ray_tmax <= root do return false, rec
  }

  rec.dist = root
  rec.pos = ray_at( ray, rec.dist )
  // rec.normal = (rec.pos - center) / radius
  outward_normal := ( rec.pos - sphere.pos ) / sphere.radius
  hit_set_face_normal( &rec, ray, outward_normal )

  return true, rec
}
// @TODO: put this in hit sphere func
hit_set_face_normal :: proc(hit: ^hit_t, ray: ray_t, outward_normal: vec3 ) 
{
  // Sets the hit record normal vector.
  // NOTE: the parameter `outward_normal` is assumed to have unit length.
  hit.front_face = linalg.dot(ray.dir, outward_normal) < 0
  hit.normal     = hit.front_face ? outward_normal : -outward_normal
}
