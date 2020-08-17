#include "splitProperties.hlsl"


cbuffer SimulationParameters : register(b0)
{
    float deltaTime;
    float totalTime;
    float strandsCount;
    float paddingForParamaters;
    uint3 dispatchSize;
    float padding2ForParameters;
};

cbuffer Properties : register(b1)
{
    float doTractrix;
    float doKnotInsertion;
    float doKnotRemoval;
    float stopIfKnotChanged;
    float4 padding;
};


RWStructuredBuffer<Strand> strands;

RWStructuredBuffer<PhysicalStrand> physicalStrands;

float sechInv(float z)
{
    //http://mathworld.wolfram.com/InverseHyperbolicSecant.html
    //return log(sqrt(1 / z - 1) * sqrt(1 / z + 1) + 1 / z);
    //But this seems to be for a complex number
    //thus
    //https://en.wikipedia.org/wiki/Inverse_hyperbolic_functions
    return log((1 + sqrt(1 - (z * z))) / z);
}

float sech(float z)
{
    //http://mathworld.wolfram.com/HyperbolicSecant.html
    //this seems to be identical with https://en.wikipedia.org/wiki/Hyperbolic_function
    return 1 / cosh(z);
}

struct TractrixStepReturn
{
    float3 NewTailPos;
    float3 NewHeadPos;
};

bool floatEqual(float a, float b, float epsilon)
{
    float sVal = a - epsilon;
    float lVal = a + epsilon;
    bool smaller = sVal < b;
    bool larger = lVal > b;
    return smaller && larger;
}

bool floatEqual(float3 a, float3 b, float3 epsilon)
{
    return floatEqual(a.x, b.x, epsilon.x) && floatEqual(a.y, b.y, epsilon.y) && floatEqual(a.z, b.z, epsilon.z);
}

bool floatEqual(float3 a, float3 b, float epsilon)
{
    bool x = floatEqual(a.x, b.x, epsilon);
    bool y = floatEqual(a.y, b.y, epsilon);
    bool z = floatEqual(a.z, b.z, epsilon);
    return x && y && z;
}

bool floatEqual(float2 a, float2 b, float2 epsilon)
{
    return floatEqual(a.x, b.x, epsilon.x) && floatEqual(a.y, b.y, epsilon.y);
}

bool floatEqual(float2 a, float2 b, float epsilon)
{
    return floatEqual(a.x, b.x, epsilon) && floatEqual(a.y, b.y, epsilon);
}

#define fEq(a, b, e) (((a - e) < b) && ((a + e) > b))
#define fNEq(a, b, e) (((a - e) > b) && ((a + e) < b))

TractrixStepReturn TractrixStep(float3 tailPos, float3 headPos, float3 desiredHeadPos)
{
    TractrixStepReturn ret;
    ret.NewHeadPos = headPos;
    ret.NewTailPos = tailPos;
        
    float3 S = desiredHeadPos - headPos;
    
    float lengthS = length(S);
        
    float L = length(headPos - tailPos);
    
    float3 T = tailPos - headPos;
      
    
    //TODO See if this still a bug
    //See if they are linear independent, if cross == (0, 0, 0) they are not
    //If they are linear dependent, just add some stuff on T to get a correct coordinate system 
    //Otherwise cross(S, T) = float3(0, 0, 0) and this is not good.
    //If they just pull it straight the tail should follow exactly the same
    float3 crossST = normalize(cross(S, T));
    if (all(isnan(crossST)))
    {
        ret.NewHeadPos = desiredHeadPos;
        ret.NewTailPos = desiredHeadPos - (headPos - tailPos);
        //strands[0].Color = float4(1, 0, 0, 1);
    }
    else
    {
        float3 Xr = normalize(S);
        
        float3 Zr = normalize(cross(S, T));
        
        float3 Yr = cross(Zr, Xr);
       
    
        float3x3 R = float3x3(Xr.x, Xr.y, Xr.z, Yr.x, Yr.y, Yr.z, Zr.x, Zr.y, Zr.z);
        
        float y = dot(Yr, T);

    
        float p_p = L * sechInv(y / L) + lengthS;
        float p_n = L * sechInv(y / L) - lengthS;
    
        //Prevent stuff from jumping to harsh, because sechInv -> infinity if x -> 0
        p_p = clamp(p_p, -100, 100);
    
        float xr_p = +lengthS - L * tanh(p_p / L);
        float xr_n = -lengthS - L * tanh(p_p / L);
    
        float xr_np_p = +lengthS - L * tanh(p_n / L);
        float xr_np_n = -lengthS - L * tanh(p_n / L);
    
        float yr_p = L * sech(p_p / L);
        float yr_n = L * sech(p_n / L);
        
    
        float3 tempPos = float3(xr_p, yr_p, 0);
        
    
    

        if (length(tailPos - desiredHeadPos) > length(tailPos - headPos))  // Replacable by 'dot(normalize(T), normalize(S)) < 0' [for performance, because length of S and T might be used elsewhere too]
        {
            tempPos = float3(xr_p, yr_p, 0);
        }
        else
        {
            // Adjustment by me. Looks more realistic, if the motion of the head is in the direction of X
            tempPos = float3(-xr_np_n, yr_n, 0);
        }
    
        
        float3 newTailPos = headPos + mul(tempPos, R);
        
        if (length(newTailPos - tailPos) < length(desiredHeadPos - headPos))
        {
            // I don´t have infinite precision and sechInv -> infinity if x -> 0 so yeah... should prevent these ehm irregularities (basically everything just fucks up)
            // Additionaly it is mathematically correct, because in a tractrix the movement of the tail has to be smaller than the movement of the head (thats the whole point of this thing)
            ret.NewTailPos = headPos + mul(tempPos, R);
            ret.NewHeadPos = desiredHeadPos;
            //strands[0].Color = float4(0, 1, 0, 1);

        }
        else
        {
            //If the calculation fails, just set the head to the desiredHeadPos and 
            //pull the tail along the control polygon. This will prevent weird cases when in which
            //the tail will follow the exact same movement as the head (like a z shape falling straight down instead of flexing)
            //strands[0].Color = float4(0, 0, 1, 1);
            ret.NewHeadPos = desiredHeadPos;
            ret.NewTailPos = tailPos + normalize(headPos - tailPos) * length(desiredHeadPos - headPos);
            ret.NewTailPos = ret.NewHeadPos + normalize(ret.NewTailPos - ret.NewHeadPos) * L;
        }
    }
    
    
    return ret;
}


void RecursiveTractrixForward(int idx, int startIndex, float3 Xp, out float3 newParticlePositions[MAX_PARTICLE_COUNT])
{
    //See sreenivasan2010.pdf
    //https://doi.org/10.1016/j.mechmachtheory.2009.10.005
    //Chapter 3.1 and 4
        
        
    /*
    // S x T --> Crossproduct; |S| --> Length of S; ^T --> Transpose
    (0) //Added from eq. 12// L^2 = (x - xe)^2 + (y - ye)^2 + (z - ze)^2
    (1) Define the vector S = Xp - Xh where Xh is the current location of the head and Xp is the destination point of the head.
    (2) Define the vector T = X - Xh where X = (x; y; z)^T is the tail of the link lying on the tractrix.
    (3) Define the new reference coordinate system frg with the X-axis along S. Hence ^Xr = S / |S|.
    (4) Define the Z-axis as ^Zr = S x T / |S x T|.
    (5) Define rotation matrix [R] = [ ^Xr; ^Zr x ^Xr; ^Zr ].
    (6) The Y-coordinate of the tail (lying on the tractrix) is given by y = dot(^Yr, T) and the parameter p can be obtained as
    p = L * sech^-1(y / L) +- |S|.
    (7) From p, we can obtain the X and Y-coordinate of the point on the tractrix in the reference coordinate system as
    xr = +- |S| - L * tanh(p / L).
    yr = L * sech(p / l).
    (8) Once xr and yr are known, the point on the tractrix (x; y; z)^T in the global fixed coordinate system {0} is given by
    (x; y; z)^T = Xh + [R]*(xr; yr; 0)^T
    */
    
    for (int i = 0; i < MAX_PARTICLE_COUNT; i++)
    {
        newParticlePositions[i] = float3(0, 0, 0);
    }
    
    if ( /*forwards && */startIndex + 1 < strands[idx].ParticlesCount)
    {
        int headParticleIdx = startIndex;
        int tailParticleIdx = headParticleIdx + 1;
        
        float3 Xh = physicalStrands[idx].PhysicalParticles[headParticleIdx].Position;
        float3 Xt = physicalStrands[idx].PhysicalParticles[tailParticleIdx].Position;
        
        headParticleIdx++;
        tailParticleIdx++;
        
        TractrixStepReturn tractrixResult;
        
        for (; tailParticleIdx < strands[idx].ParticlesCount; headParticleIdx++, tailParticleIdx++)
        {
            tractrixResult = TractrixStep(Xt, Xh, Xp);
        
            Xh = physicalStrands[idx].PhysicalParticles[headParticleIdx].Position;
            Xt = physicalStrands[idx].PhysicalParticles[tailParticleIdx].Position;
            Xp = tractrixResult.NewTailPos;
            
            newParticlePositions[tailParticleIdx - 1] = tractrixResult.NewTailPos;
        }
        
        tractrixResult = TractrixStep(Xt, Xh, Xp);
        
        newParticlePositions[tailParticleIdx - 1] = tractrixResult.NewTailPos;
    }
}

void RecursiveTractrixBackward(int idx, int startIndex, float3 Xp, out float3 newParticlePositions[MAX_PARTICLE_COUNT])
{
    //See sreenivasan2010.pdf
    //https://doi.org/10.1016/j.mechmachtheory.2009.10.005
    //Chapter 3.1 and 4
        
        
    /*
    // S x T --> Crossproduct; |S| --> Length of S; ^T --> Transpose
    (0) //Added from eq. 12// L^2 = (x - xe)^2 + (y - ye)^2 + (z - ze)^2
    (1) Define the vector S = Xp - Xh where Xh is the current location of the head and Xp is the destination point of the head.
    (2) Define the vector T = X - Xh where X = (x; y; z)^T is the tail of the link lying on the tractrix.
    (3) Define the new reference coordinate system frg with the X-axis along S. Hence ^Xr = S / |S|.
    (4) Define the Z-axis as ^Zr = S x T / |S x T|.
    (5) Define rotation matrix [R] = [ ^Xr; ^Zr x ^Xr; ^Zr ].
    (6) The Y-coordinate of the tail (lying on the tractrix) is given by y = dot(^Yr, T) and the parameter p can be obtained as
    p = L * sech^-1(y / L) +- |S|.
    (7) From p, we can obtain the X and Y-coordinate of the point on the tractrix in the reference coordinate system as
    xr = +- |S| - L * tanh(p / L).
    yr = L * sech(p / l).
    (8) Once xr and yr are known, the point on the tractrix (x; y; z)^T in the global fixed coordinate system {0} is given by
    (x; y; z)^T = Xh + [R]*(xr; yr; 0)^T
    */
    
    for (int i = 0; i < MAX_PARTICLE_COUNT; i++)
    {
        newParticlePositions[i] = float3(0, 0, 0);
    }

    if ( /*!forwards && */startIndex - 1 >= 0)
    {
        int headParticleIdx = startIndex;
        int tailParticleIdx = headParticleIdx - 1;
        
        float3 Xh = physicalStrands[idx].PhysicalParticles[headParticleIdx].Position;
        float3 Xt = physicalStrands[idx].PhysicalParticles[tailParticleIdx].Position;
        
        headParticleIdx--;
        tailParticleIdx--;
        
        TractrixStepReturn tractrixResult;
        
        for (int i = 0; i < MAX_PARTICLE_COUNT; i++)
        {
            tractrixResult = TractrixStep(Xt, Xh, Xp);
        
            Xh = physicalStrands[idx].PhysicalParticles[max(headParticleIdx - i, 0)].Position;
            Xt = physicalStrands[idx].PhysicalParticles[max(tailParticleIdx - i, 0)].Position;
            Xp = tractrixResult.NewTailPos;
            
            float idxAcessable = step(-0.5, tailParticleIdx - i + 1);
            newParticlePositions[max(tailParticleIdx - i + 1, 0)] = tractrixResult.NewTailPos * idxAcessable + newParticlePositions[max(tailParticleIdx - i + 1, 0)] * (1 - idxAcessable);
        }
    }
}

float random(float2 st)
{
    return frac(sin(dot(st.xy, float2(12.9898, 78.233))) * 43758.5453123);
}

// Special Thanks to Johnathan, Shaun and Geof!
// And to the author of this website ^^: https://keithmaggio.wordpress.com/2011/02/15/math-magician-lerp-slerp-and-nlerp/
float3 Slerp(float3 start, float3 end, float percent)
{
     // Dot product - the cosine of the angle between 2 vectors.
    float dotPrd = dot(start, end);
     // Clamp it to be in the range of Acos()
     // This may be unnecessary, but floating point
     // precision can be a fickle mistress.
    dotPrd = clamp(dotPrd, -1.0f, 1.0f);
     // Acos(dot) returns the angle between start and end,
     // And multiplying that by percent returns the angle between
     // start and the final result.
    float theta = acos(dotPrd) * percent;
    float3 RelativeVec = normalize(end - start * dotPrd);
     // Orthonormal basis
     // The final result.
    return ((start * cos(theta)) + (RelativeVec * sin(theta)));
}

static const int3 numThreads = int3(1, 1, 1);

[numthreads(numThreads.x, numThreads.y, numThreads.z)]
void Simulation(uint3 DTid : SV_DispatchThreadID)
{
    //TODO Something is not right if x and y direction is used
    int idx = DTid.x * 1 + DTid.y * dispatchSize.x + DTid.z * dispatchSize.x * dispatchSize.y;
    
    if (idx >= strandsCount)
        return;
    
   
    
    if (doTractrix && !(stopIfKnotChanged && strands[idx].KnotHasChangedOnce))
    {
        float3 Xp = strands[idx].OriginalHeadPosition;
        float timeDialation = 1;
   
        float3 originalPosition[MAX_PARTICLE_COUNT];
        for (int op_i = 0; op_i < MAX_PARTICLE_COUNT; op_i++)
        {
            originalPosition[op_i] = physicalStrands[idx].PhysicalParticles[op_i].Position;
        }
    
        //Get the old segment length of each segment, to maintain the strand structure
        float oldSegmentLength[MAX_PARTICLE_COUNT - 1];
        for (int u = 0; u < MAX_PARTICLE_COUNT - 1; u++)
        {
            oldSegmentLength[u] = length(physicalStrands[idx].PhysicalParticles[u].Position - physicalStrands[idx].PhysicalParticles[u + 1].Position);
        }
    
    
        float3 desiredPosition[MAX_PARTICLE_COUNT];
        for (int dp_i = 0; dp_i < MAX_PARTICLE_COUNT; dp_i++)
        {
            desiredPosition[dp_i] = physicalStrands[idx].PhysicalParticles[dp_i].Position;
        }
    
        desiredPosition[0] = strands[idx].HairRoot;
    

        
        //Save desired position of every particle if they would move independently (except the root)
        //The root does not have a desiredPosition, because it does not move on its own and if the head moves, than the movement is covered by the backpull
        for (int i = 1; i < MAX_PARTICLE_COUNT; i++)
        {
            physicalStrands[idx].PhysicalParticles[i].Velocity += float3(0, -9.81, 0) * deltaTime * timeDialation;
            //physicalStrands[idx].PhysicalParticles[i].Velocity += float3(sin(totalTime * 5) * 3, 0, 0) * deltaTime * timeDialation;
            //physicalStrands[idx].PhysicalParticles[i].Velocity += float3(0, 0, sin(totalTime * 3) * 4) * deltaTime * timeDialation;
            //physicalStrands[idx].PhysicalParticles[i].Velocity += float3((step(sin(totalTime * 0.5), 0) - 0.5) * 5, 0, 0) * deltaTime * timeDialation;
            physicalStrands[idx].PhysicalParticles[i].Velocity += -(physicalStrands[idx].PhysicalParticles[i].Velocity) * deltaTime * 4.0; // Simple drag
            
            
        
        
            //Drag force by air resistance
            float airDensity = 1.2; //Density of air see: https://en.wikipedia.org/wiki/Density
            float3 velocitySquare = pow(physicalStrands[idx].PhysicalParticles[i].Velocity, float3(2, 2, 2));
            float dragCoefficient = 0.47; //Hair should be roughtly a sphere see https://en.wikipedia.org/wiki/Drag_coefficient
            float crossSection = (0.1 / 10) * oldSegmentLength[i - 1]; //Diameter of hair (ranges from 0.017mm to 0.18mm see https://en.wikipedia.org/wiki/Hair thus ~0.1mm thus 0.01cm)[right now I am in cm/s^2 for gravity]
            float3 dragForce = 0.5 * airDensity * velocitySquare * dragCoefficient * crossSection;
            
        
            physicalStrands[idx].PhysicalParticles[i].Velocity -= sign(physicalStrands[idx].PhysicalParticles[i].Velocity) * abs(dragForce) * deltaTime;
        
            float3 currentPosition = physicalStrands[idx].PhysicalParticles[i].Position;
            float3 vel = physicalStrands[idx].PhysicalParticles[i].Velocity;
            desiredPosition[i] = currentPosition + vel * deltaTime;
        }
        
    

        
        float3 forwardpullPositions[MAX_PARTICLE_COUNT];
        for (int forwardpullZero_i = 0; forwardpullZero_i < MAX_PARTICLE_COUNT; forwardpullZero_i++)
        {
            forwardpullPositions[forwardpullZero_i] = float3(0, 0, 0);
        }

        RecursiveTractrixBackward(idx, strands[idx].ParticlesCount - 1, desiredPosition[strands[idx].ParticlesCount - 1], forwardpullPositions);
        forwardpullPositions[strands[idx].ParticlesCount - 1] = desiredPosition[strands[idx].ParticlesCount - 1];
        
        for (int setForwardpullPos_i = 0; setForwardpullPos_i < MAX_PARTICLE_COUNT; setForwardpullPos_i++)
        {
            physicalStrands[idx].PhysicalParticles[setForwardpullPos_i].Position = forwardpullPositions[setForwardpullPos_i];
        }
        
        
        
        float3 backpullPositions[MAX_PARTICLE_COUNT];
        for (int backpullZero_i = 0; backpullZero_i < MAX_PARTICLE_COUNT; backpullZero_i++)
        {
            backpullPositions[backpullZero_i] = float3(0, 0, 0);
        }

        RecursiveTractrixForward(idx, 0, strands[idx].HairRoot, backpullPositions);
        
        backpullPositions[0] = strands[idx].HairRoot;
        
        for (int setBackpullPos_i = 0; setBackpullPos_i < MAX_PARTICLE_COUNT; setBackpullPos_i++)
        {
            physicalStrands[idx].PhysicalParticles[setBackpullPos_i].Position = backpullPositions[setBackpullPos_i];
        }
        
        
        for (int setForce_i = 0; setForce_i < MAX_PARTICLE_COUNT; setForce_i++)
        {
            float3 normVel = normalize(physicalStrands[idx].PhysicalParticles[setForce_i].Velocity);
            float3 velLen = length(physicalStrands[idx].PhysicalParticles[setForce_i].Velocity);
            float3 movementLen = length(physicalStrands[idx].PhysicalParticles[setForce_i].Position - originalPosition[setForce_i]);
            if (all(!isnan(normVel)))
            {
                physicalStrands[idx].PhysicalParticles[setForce_i].Velocity = normVel * max(velLen, movementLen);
            }

        }
        
        
        float3 currentPos = strands[idx].HairRoot;
        for (int setFinalPos_i = 1; setFinalPos_i < strands[idx].ParticlesCount; setFinalPos_i++)
        {
            strands[idx].Particles[setFinalPos_i].Position = currentPos;
            float3 physicalSegmentDir = physicalStrands[idx].PhysicalParticles[setFinalPos_i].Position - physicalStrands[idx].PhysicalParticles[setFinalPos_i - 1].Position;
            float hairStyleFactor = 0.2;
            currentPos = currentPos + Slerp(normalize(physicalSegmentDir), normalize(strands[idx].DesiredSegmentDirections[setFinalPos_i - 1]), hairStyleFactor) * oldSegmentLength[setFinalPos_i - 1];

        }

    }
}