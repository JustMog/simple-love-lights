local lg = love.graphics

-- Shader for caculating the 1D shadow map.
local shadowMapShader = lg.newShader([[
	#define PI 3.14

    uniform float yResolution;
    uniform float alphaThreshold;
	uniform float overlap;

	vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
		float distance = 1.0;
		
		// Iterate through the occluder map's y-axis.
		for (number y = 0.0; y < yResolution; y++) {

			// Rectangular to polar
			vec2 norm = vec2(texture_coords.s, y / yResolution) * 2.0 - 1.0;
			float theta = PI * 1.5 + norm.x * PI; 
			float r = (1.0 + norm.y) * 0.5;

			//coord which we will sample from occlude map
			vec2 coord = vec2(-r * sin(theta), -r * cos(theta)) / 2.0 + 0.5;
	
			//sample the occlusion map
			vec4 data = Texel(texture, coord);
	
			//if we've hit an opaque fragment (occluder)
			if (data.a >= alphaThreshold) {
            
				//the distance is how far from the top we've come
				distance = y / yResolution;
			
				//add some to cover up seams
				distance += overlap/yResolution;

				break;
			}

		}
		return vec4(vec3(distance), 1.0);
	}
]])

-- Shader for rendering blurred lights and shadows.
local lightRenderShader = lg.newShader([[
	#define PI 3.14

	uniform float xResolution;
    uniform float falloff;
    uniform float steps;
	uniform float radius;
	uniform float noise;

	//sample from the 1D distance map
	number sample(vec2 coord, number r, Image u_texture) {
		return step(r, Texel(u_texture, coord).r);
	}

	float rand(float n){
		return abs(sin(n * 999999));
	}

	vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
		// Transform rectangular to polar coordinates.
		vec2 norm = texture_coords.st * 2.0 - 1.0;
		float theta = atan(norm.y, norm.x);
		float r = length(norm);	
		float coord = (theta + PI) / (2.0 * PI);
		
		// The tex coordinate to sample our 1D lookup texture.
		//always 0.0 on y axis
		vec2 tc = vec2(coord, 0.0);
		
		// The center tex coord, which gives us hard shadows.
		number center = sample(tc, r, texture);        
		
	 	// Multiply the summed amount by our distance, which gives us a radial falloff.

		r /= radius / (xResolution / 2.0);
		r = smoothstep(1.0, 0.0, r);
		r = pow(r, falloff);
		
		float a = center * r;
		a += rand(rand(rand(coord))) * noise * a;

        float stps = steps + 1;
		if(steps > 0) a = floor(a * stps) /  stps;
	
	 	return vec4(vec3(1.0), a);
	}
]])

local Light = {
    overlap = 5,
    alphaThreshold = 1,
    falloff = 1,
    steps = -1,
	noise = 0.03,
}
Light.__index = Light

local function newLight(self, x, y, maxRadius, color)
    local size = maxRadius * 2
    color = color or {1, 1, 1, 1}

    local light = {
        x = x, y = y,
        radius = maxRadius,
        color = color,
        _occludersCanvas = lg.newCanvas(size, size),
		_shadowMapCanvas = lg.newCanvas(size, 1),
		_lightRenderCanvas = lg.newCanvas(size, size),
    }
    return setmetatable(light, Light)
end

function Light:getMaxRadius()
   return self._lightRenderCanvas:getWidth()/2
end

function Light:updateCanvas(drawOccludersFn)
    local size = self._lightRenderCanvas:getWidth()
    if self.radius <= 0 then return end
    assert(self.radius <= size/2, "light's radius exceeded maximum set at creation")

    self._occludersCanvas:renderTo(function() lg.clear() end)
    self._shadowMapCanvas:renderTo(function() lg.clear() end)
    self._lightRenderCanvas:renderTo(function() lg.clear() end)

    shadowMapShader:send("yResolution", size)
    shadowMapShader:send("alphaThreshold", self.alphaThreshold)
    shadowMapShader:send("overlap", self.overlap)

    lightRenderShader:send("xResolution", size)
	lightRenderShader:send("radius", self.radius)
    lightRenderShader:send("falloff", self.falloff)
    lightRenderShader:send("steps", self.steps)
	lightRenderShader:send("noise", self.noise)

    lg.push("all")
    lg.origin()

    local left, top = self.x - size/2, self.y - size/2
    lg.translate(-left, -top)
    self._occludersCanvas:renderTo(drawOccludersFn)
    lg.translate(left, top)

    lg.setShader(shadowMapShader)
	lg.setCanvas(self._shadowMapCanvas)
	lg.draw(self._occludersCanvas, 0, 0)

	lg.setShader(lightRenderShader)
	lg.setCanvas(self._lightRenderCanvas)
	lg.draw(self._shadowMapCanvas, 0, 0, 0, 1, size)

	lg.setCanvas()
	lg.setShader()

    lg.pop()
end

function Light:draw(blendMode)
    local size = self._lightRenderCanvas:getWidth()
    local x, y = self.x - size/2, self.y - size/2

    lg.push("all")
	lg.setBlendMode(blendMode or "add")
    self.color[4] = self.color[4] or 1
	lg.setColor(unpack(self.color))
	lg.draw(self._lightRenderCanvas, x, y + size, 0, 1, -1)
	lg.pop()

end

function Light:getCanvas()
   return self._lightRenderCanvas
end

return setmetatable({
    setDefaults = function(opts)
        Light.overlap = opts.overlap or Light.overlap
        Light.alphaThreshold = opts.alphaThreshold or Light.alphaThreshold
        Light.falloff = opts.falloff or Light.falloff
        Light.steps = opts.steps or Light.steps
		Light.noise = opts.noise or Light.noise
    end,
},{ __call = newLight })