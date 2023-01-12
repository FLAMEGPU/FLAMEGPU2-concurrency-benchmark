#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <fstream>
#include <chrono>

#include "flamegpu/flamegpu.h"

/**
 * FLAME GPU 2 concurrency benchmark, using an implementation of the Boids flocking model.
 */

/**
 * Get the length of a vector
 * @param x x component of the vector
 * @param y y component of the vector
 * @param z z component of the vector
 * @return the length of the vector
 */ 
FLAMEGPU_HOST_DEVICE_FUNCTION float vec3Length(const float x, const float y, const float z) {
    return sqrtf(x * x + y * y + z * z);
}

/**
 * Add a scalar to a vector in-place
 * @param x x component of the vector
 * @param y y component of the vector
 * @param z z component of the vector
 * @param value scalar value to add
 */ 
FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Add(float &x, float &y, float &z, const float value) {
    x += value;
    y += value;
    z += value;
}

/**
 * Subtract a scalar from a vector in-place
 * @param x x component of the vector
 * @param y y component of the vector
 * @param z z component of the vector
 * @param value scalar value to subtract
 */ 
FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Sub(float &x, float &y, float &z, const float value) {
    x -= value;
    y -= value;
    z -= value;
}

/**
 * Multiply a vector by a scalar value in-place
 * @param x x component of the vector
 * @param y y component of the vector
 * @param z z component of the vector
 * @param multiplier scalar value to multiply by
 */ 
FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Mult(float &x, float &y, float &z, const float multiplier) {
    x *= multiplier;
    y *= multiplier;
    z *= multiplier;
}

/**
 * Divide a vector by a scalar value in-place
 * @param x x component of the vector
 * @param y y component of the vector
 * @param z z component of the vector
 * @param divisor scalar value to divide by
 */ 
FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Div(float &x, float &y, float &z, const float divisor) {
    x /= divisor;
    y /= divisor;
    z /= divisor;
}

/**
 * Normalize a 3 component vector in-place
 * @param x x component of the vector
 * @param y y component of the vector
 * @param z z component of the vector
 */ 
FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Normalize(float &x, float &y, float &z) {
    // Get the length
    float length = vec3Length(x, y, z);
    vec3Div(x, y, z, length);
}

/**
 * Clamp each component of a 3-part position to lie within a minimum and maximum value.
 * Performs the operation in place
 * Unlike the FLAME GPU 1 example, this is a clamping operation, rather than wrapping.
 * @param x x component of the vector
 * @param y y component of the vector
 * @param z z component of the vector
 * @param MIN_POSITION the minimum value for each component
 * @param MAX_POSITION the maximum value for each component
 */
FLAMEGPU_HOST_DEVICE_FUNCTION void clampPosition(float &x, float &y, float &z, const float MIN_POSITION, const float MAX_POSITION) {
    x = (x < MIN_POSITION)? MIN_POSITION: x;
    x = (x > MAX_POSITION)? MAX_POSITION: x;

    y = (y < MIN_POSITION)? MIN_POSITION: y;
    y = (y > MAX_POSITION)? MAX_POSITION: y;

    z = (z < MIN_POSITION)? MIN_POSITION: z;
    z = (z > MAX_POSITION)? MAX_POSITION: z;
}

/**
 * outputdata agent function for Boid agents, which outputs publicly visible properties to a message list
 */
const char* outputdata = R"###(
FLAMEGPU_AGENT_FUNCTION(outputdata, flamegpu::MessageNone, flamegpu::MessageSpatial3D) {
    // Output each agents publicly visible properties.
    FLAMEGPU->message_out.setVariable<int>("id", FLAMEGPU->getVariable<int>("id"));
    FLAMEGPU->message_out.setVariable<float>("x", FLAMEGPU->getVariable<float>("x"));
    FLAMEGPU->message_out.setVariable<float>("y", FLAMEGPU->getVariable<float>("y"));
    FLAMEGPU->message_out.setVariable<float>("z", FLAMEGPU->getVariable<float>("z"));
    FLAMEGPU->message_out.setVariable<float>("fx", FLAMEGPU->getVariable<float>("fx"));
    FLAMEGPU->message_out.setVariable<float>("fy", FLAMEGPU->getVariable<float>("fy"));
    FLAMEGPU->message_out.setVariable<float>("fz", FLAMEGPU->getVariable<float>("fz"));
    return flamegpu::ALIVE;
}
)###";

const char* outputdataBruteForce = R"###(
    FLAMEGPU_AGENT_FUNCTION(outputdata, flamegpu::MessageNone, flamegpu::MessageBruteForce) {
        // Output each agents publicly visible properties.
        FLAMEGPU->message_out.setVariable<int>("id", FLAMEGPU->getVariable<int>("id"));
        FLAMEGPU->message_out.setVariable<float>("x", FLAMEGPU->getVariable<float>("x"));
        FLAMEGPU->message_out.setVariable<float>("y", FLAMEGPU->getVariable<float>("y"));
        FLAMEGPU->message_out.setVariable<float>("z", FLAMEGPU->getVariable<float>("z"));
        FLAMEGPU->message_out.setVariable<float>("fx", FLAMEGPU->getVariable<float>("fx"));
        FLAMEGPU->message_out.setVariable<float>("fy", FLAMEGPU->getVariable<float>("fy"));
        FLAMEGPU->message_out.setVariable<float>("fz", FLAMEGPU->getVariable<float>("fz"));
        return flamegpu::ALIVE;
    }
    )###";
/**
 * inputdata agent function for Boid agents, which reads data from neighbouring Boid agents, to perform the boid flocking model.
 */
const char* inputdata = R"###(
// Vector utility functions, see top of file for versions with commentary
FLAMEGPU_HOST_DEVICE_FUNCTION float vec3Length(const float x, const float y, const float z) {
    return sqrtf(x * x + y * y + z * z);
}
FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Add(float &x, float &y, float &z, const float value) {
    x += value;
    y += value;
    z += value;
}
FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Sub(float &x, float &y, float &z, const float value) {
    x -= value;
    y -= value;
    z -= value;
}
FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Mult(float &x, float &y, float &z, const float multiplier) {
    x *= multiplier;
    y *= multiplier;
    z *= multiplier;
}
FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Div(float &x, float &y, float &z, const float divisor) {
    x /= divisor;
    y /= divisor;
    z /= divisor;
}
FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Normalize(float &x, float &y, float &z) {
    // Get the length
    float length = vec3Length(x, y, z);
    vec3Div(x, y, z, length);
}
FLAMEGPU_HOST_DEVICE_FUNCTION void clampPosition(float &x, float &y, float &z, const float MIN_POSITION, const float MAX_POSITION) {
    x = (x < MIN_POSITION)? MIN_POSITION: x;
    x = (x > MAX_POSITION)? MAX_POSITION: x;

    y = (y < MIN_POSITION)? MIN_POSITION: y;
    y = (y > MAX_POSITION)? MAX_POSITION: y;

    z = (z < MIN_POSITION)? MIN_POSITION: z;
    z = (z > MAX_POSITION)? MAX_POSITION: z;
}
// Agent function
FLAMEGPU_AGENT_FUNCTION(inputdata, flamegpu::MessageSpatial3D, flamegpu::MessageNone) {
    // Agent properties in local register
    const flamegpu::id_t id = FLAMEGPU->getID();
    // Agent position
    float agent_x = FLAMEGPU->getVariable<float>("x");
    float agent_y = FLAMEGPU->getVariable<float>("y");
    float agent_z = FLAMEGPU->getVariable<float>("z");
    // Agent velocity
    float agent_fx = FLAMEGPU->getVariable<float>("fx");
    float agent_fy = FLAMEGPU->getVariable<float>("fy");
    float agent_fz = FLAMEGPU->getVariable<float>("fz");

    // Boids percieved center
    float perceived_centre_x = 0.0f;
    float perceived_centre_y = 0.0f;
    float perceived_centre_z = 0.0f;
    int perceived_count = 0;

    // Boids global velocity matching
    float global_velocity_x = 0.0f;
    float global_velocity_y = 0.0f;
    float global_velocity_z = 0.0f;

    // Total change in velocity
    float velocity_change_x = 0.f;
    float velocity_change_y = 0.f;
    float velocity_change_z = 0.f;

    const float INTERACTION_RADIUS = FLAMEGPU->environment.getProperty<float>("INTERACTION_RADIUS");
    const float SEPARATION_RADIUS = FLAMEGPU->environment.getProperty<float>("SEPARATION_RADIUS");
    // Iterate location messages, accumulating relevant data and counts.
    for (const auto &message : FLAMEGPU->message_in(agent_x, agent_y, agent_z)) {
        // Ignore self messages.
        if (message.getVariable<flamegpu::id_t>("id") != id) {
            // Get the message location and velocity.
            const float message_x = message.getVariable<float>("x");
            const float message_y = message.getVariable<float>("y");
            const float message_z = message.getVariable<float>("z");

            // Check interaction radius
            float separation = vec3Length(agent_x - message_x, agent_y - message_y, agent_z - message_z);

            if (separation < INTERACTION_RADIUS) {
                // Update the percieved centre
                perceived_centre_x += message_x;
                perceived_centre_y += message_y;
                perceived_centre_z += message_z;
                perceived_count++;

                // Update percieved velocity matching
                const float message_fx = message.getVariable<float>("fx");
                const float message_fy = message.getVariable<float>("fy");
                const float message_fz = message.getVariable<float>("fz");
                global_velocity_x += message_fx;
                global_velocity_y += message_fy;
                global_velocity_z += message_fz;

                // Update collision centre
                if (separation < (SEPARATION_RADIUS)) {  // dependant on model size
                    // Rule 3) Avoid other nearby boids (Separation)
                    float normalizedSeparation = (separation / SEPARATION_RADIUS);
                    float invNormSep = (1.0f - normalizedSeparation);
                    float invSqSep = invNormSep * invNormSep;

                    const float collisionScale = FLAMEGPU->environment.getProperty<float>("COLLISION_SCALE");
                    velocity_change_x += collisionScale * (agent_x - message_x) * invSqSep;
                    velocity_change_y += collisionScale * (agent_y - message_y) * invSqSep;
                    velocity_change_z += collisionScale * (agent_z - message_z) * invSqSep;
                }
            }
        }
    }

    if (perceived_count) {
        // Divide positions/velocities by relevant counts.
        vec3Div(perceived_centre_x, perceived_centre_y, perceived_centre_z, perceived_count);
        vec3Div(global_velocity_x, global_velocity_y, global_velocity_z, perceived_count);

        // Rule 1) Steer towards perceived centre of flock (Cohesion)
        float steer_velocity_x = 0.f;
        float steer_velocity_y = 0.f;
        float steer_velocity_z = 0.f;

        const float STEER_SCALE = FLAMEGPU->environment.getProperty<float>("STEER_SCALE");
        steer_velocity_x = (perceived_centre_x - agent_x) * STEER_SCALE;
        steer_velocity_y = (perceived_centre_y - agent_y) * STEER_SCALE;
        steer_velocity_z = (perceived_centre_z - agent_z) * STEER_SCALE;

        velocity_change_x += steer_velocity_x;
        velocity_change_y += steer_velocity_y;
        velocity_change_z += steer_velocity_z;

        // Rule 2) Match neighbours speeds (Alignment)
        float match_velocity_x = 0.f;
        float match_velocity_y = 0.f;
        float match_velocity_z = 0.f;

        const float MATCH_SCALE = FLAMEGPU->environment.getProperty<float>("MATCH_SCALE");
        match_velocity_x = global_velocity_x;
        match_velocity_y = global_velocity_y;
        match_velocity_z = global_velocity_z;

        velocity_change_x += (match_velocity_x - agent_fx) * MATCH_SCALE;
        velocity_change_y += (match_velocity_y - agent_fy) * MATCH_SCALE;
        velocity_change_z += (match_velocity_z - agent_fz) * MATCH_SCALE;
    }

    // Global scale of velocity change
    vec3Mult(velocity_change_x, velocity_change_y, velocity_change_z, FLAMEGPU->environment.getProperty<float>("GLOBAL_SCALE"));

    // Update agent velocity
    agent_fx += velocity_change_x;
    agent_fy += velocity_change_y;
    agent_fz += velocity_change_z;

    // Bound velocity
    float agent_fscale = vec3Length(agent_fx, agent_fy, agent_fz);
    if (agent_fscale > 1) {
        vec3Div(agent_fx, agent_fy, agent_fz, agent_fscale);
    }

    float minSpeed = 0.5f;
    if (agent_fscale < minSpeed) {
        // Normalise
        vec3Div(agent_fx, agent_fy, agent_fz, agent_fscale);

        // Scale to min
        vec3Mult(agent_fx, agent_fy, agent_fz, minSpeed);
    }

    // Steer away from walls - Computed post normalization to ensure good avoidance. Prevents constant term getting swamped
    const float wallInteractionDistance = 0.10f;
    const float wallSteerStrength = 0.05f;
    const float minPosition = FLAMEGPU->environment.getProperty<float>("MIN_POSITION");
    const float maxPosition = FLAMEGPU->environment.getProperty<float>("MAX_POSITION");

    if (agent_x - minPosition < wallInteractionDistance) {
        agent_fx += wallSteerStrength;
    }
    if (agent_y - minPosition < wallInteractionDistance) {
        agent_fy += wallSteerStrength;
    }
    if (agent_z - minPosition < wallInteractionDistance) {
        agent_fz += wallSteerStrength;
    }

    if (maxPosition - agent_x < wallInteractionDistance) {
        agent_fx -= wallSteerStrength;
    }
    if (maxPosition - agent_y < wallInteractionDistance) {
        agent_fy -= wallSteerStrength;
    }
    if (maxPosition - agent_z < wallInteractionDistance) {
        agent_fz -= wallSteerStrength;
    }

    // Apply the velocity
    const float TIME_SCALE = FLAMEGPU->environment.getProperty<float>("TIME_SCALE");
    agent_x += agent_fx * TIME_SCALE;
    agent_y += agent_fy * TIME_SCALE;
    agent_z += agent_fz * TIME_SCALE;

    // Bound position
    clampPosition(agent_x, agent_y, agent_z, FLAMEGPU->environment.getProperty<float>("MIN_POSITION"), FLAMEGPU->environment.getProperty<float>("MAX_POSITION"));

    // Update global agent memory.
    FLAMEGPU->setVariable<float>("x", agent_x);
    FLAMEGPU->setVariable<float>("y", agent_y);
    FLAMEGPU->setVariable<float>("z", agent_z);

    FLAMEGPU->setVariable<float>("fx", agent_fx);
    FLAMEGPU->setVariable<float>("fy", agent_fy);
    FLAMEGPU->setVariable<float>("fz", agent_fz);

    return flamegpu::ALIVE;
}
)###";

const char* inputdataBruteForce = R"###(
    // Vector utility functions, see top of file for versions with commentary
    FLAMEGPU_HOST_DEVICE_FUNCTION float vec3Length(const float x, const float y, const float z) {
        return sqrtf(x * x + y * y + z * z);
    }
    FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Add(float &x, float &y, float &z, const float value) {
        x += value;
        y += value;
        z += value;
    }
    FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Sub(float &x, float &y, float &z, const float value) {
        x -= value;
        y -= value;
        z -= value;
    }
    FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Mult(float &x, float &y, float &z, const float multiplier) {
        x *= multiplier;
        y *= multiplier;
        z *= multiplier;
    }
    FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Div(float &x, float &y, float &z, const float divisor) {
        x /= divisor;
        y /= divisor;
        z /= divisor;
    }
    FLAMEGPU_HOST_DEVICE_FUNCTION void vec3Normalize(float &x, float &y, float &z) {
        // Get the length
        float length = vec3Length(x, y, z);
        vec3Div(x, y, z, length);
    }
    FLAMEGPU_HOST_DEVICE_FUNCTION void clampPosition(float &x, float &y, float &z, const float MIN_POSITION, const float MAX_POSITION) {
        x = (x < MIN_POSITION)? MIN_POSITION: x;
        x = (x > MAX_POSITION)? MAX_POSITION: x;
    
        y = (y < MIN_POSITION)? MIN_POSITION: y;
        y = (y > MAX_POSITION)? MAX_POSITION: y;
    
        z = (z < MIN_POSITION)? MIN_POSITION: z;
        z = (z > MAX_POSITION)? MAX_POSITION: z;
    }
    // Agent function
    FLAMEGPU_AGENT_FUNCTION(inputdata, flamegpu::MessageBruteForce, flamegpu::MessageNone) {
    // Agent properties in local register
    const flamegpu::id_t id = FLAMEGPU->getID();
    // Agent position
    float agent_x = FLAMEGPU->getVariable<float>("x");
    float agent_y = FLAMEGPU->getVariable<float>("y");
    float agent_z = FLAMEGPU->getVariable<float>("z");
    // Agent velocity
    float agent_fx = FLAMEGPU->getVariable<float>("fx");
    float agent_fy = FLAMEGPU->getVariable<float>("fy");
    float agent_fz = FLAMEGPU->getVariable<float>("fz");

    // Boids percieved center
    float perceived_centre_x = 0.0f;
    float perceived_centre_y = 0.0f;
    float perceived_centre_z = 0.0f;
    int perceived_count = 0;

    // Boids global velocity matching
    float global_velocity_x = 0.0f;
    float global_velocity_y = 0.0f;
    float global_velocity_z = 0.0f;

    // Total change in velocity
    float velocity_change_x = 0.f;
    float velocity_change_y = 0.f;
    float velocity_change_z = 0.f;

    const float INTERACTION_RADIUS = FLAMEGPU->environment.getProperty<float>("INTERACTION_RADIUS");
    const float SEPARATION_RADIUS = FLAMEGPU->environment.getProperty<float>("SEPARATION_RADIUS");
    // Iterate location messages, accumulating relevant data and counts.
    for (const auto &message : FLAMEGPU->message_in) {
        // Ignore self messages.
        if (message.getVariable<flamegpu::id_t>("id") != id) {
            // Get the message location and velocity.
            const float message_x = message.getVariable<float>("x");
            const float message_y = message.getVariable<float>("y");
            const float message_z = message.getVariable<float>("z");

            // Check interaction radius
            float separation = vec3Length(agent_x - message_x, agent_y - message_y, agent_z - message_z);

            if (separation < INTERACTION_RADIUS) {
                // Update the percieved centre
                perceived_centre_x += message_x;
                perceived_centre_y += message_y;
                perceived_centre_z += message_z;
                perceived_count++;

                // Update percieved velocity matching
                const float message_fx = message.getVariable<float>("fx");
                const float message_fy = message.getVariable<float>("fy");
                const float message_fz = message.getVariable<float>("fz");
                global_velocity_x += message_fx;
                global_velocity_y += message_fy;
                global_velocity_z += message_fz;

                // Update collision centre
                if (separation < (SEPARATION_RADIUS)) {  // dependant on model size
                    // Rule 3) Avoid other nearby boids (Separation)
                    float normalizedSeparation = (separation / SEPARATION_RADIUS);
                    float invNormSep = (1.0f - normalizedSeparation);
                    float invSqSep = invNormSep * invNormSep;

                    const float collisionScale = FLAMEGPU->environment.getProperty<float>("COLLISION_SCALE");
                    velocity_change_x += collisionScale * (agent_x - message_x) * invSqSep;
                    velocity_change_y += collisionScale * (agent_y - message_y) * invSqSep;
                    velocity_change_z += collisionScale * (agent_z - message_z) * invSqSep;
                }
            }
        }
    }

    if (perceived_count) {
        // Divide positions/velocities by relevant counts.
        vec3Div(perceived_centre_x, perceived_centre_y, perceived_centre_z, perceived_count);
        vec3Div(global_velocity_x, global_velocity_y, global_velocity_z, perceived_count);

        // Rule 1) Steer towards perceived centre of flock (Cohesion)
        float steer_velocity_x = 0.f;
        float steer_velocity_y = 0.f;
        float steer_velocity_z = 0.f;

        const float STEER_SCALE = FLAMEGPU->environment.getProperty<float>("STEER_SCALE");
        steer_velocity_x = (perceived_centre_x - agent_x) * STEER_SCALE;
        steer_velocity_y = (perceived_centre_y - agent_y) * STEER_SCALE;
        steer_velocity_z = (perceived_centre_z - agent_z) * STEER_SCALE;

        velocity_change_x += steer_velocity_x;
        velocity_change_y += steer_velocity_y;
        velocity_change_z += steer_velocity_z;

        // Rule 2) Match neighbours speeds (Alignment)
        float match_velocity_x = 0.f;
        float match_velocity_y = 0.f;
        float match_velocity_z = 0.f;

        const float MATCH_SCALE = FLAMEGPU->environment.getProperty<float>("MATCH_SCALE");
        match_velocity_x = global_velocity_x;
        match_velocity_y = global_velocity_y;
        match_velocity_z = global_velocity_z;

        velocity_change_x += (match_velocity_x - agent_fx) * MATCH_SCALE;
        velocity_change_y += (match_velocity_y - agent_fy) * MATCH_SCALE;
        velocity_change_z += (match_velocity_z - agent_fz) * MATCH_SCALE;
    }

    // Global scale of velocity change
    vec3Mult(velocity_change_x, velocity_change_y, velocity_change_z, FLAMEGPU->environment.getProperty<float>("GLOBAL_SCALE"));

    // Update agent velocity
    agent_fx += velocity_change_x;
    agent_fy += velocity_change_y;
    agent_fz += velocity_change_z;

    // Bound velocity
    float agent_fscale = vec3Length(agent_fx, agent_fy, agent_fz);
    if (agent_fscale > 1) {
        vec3Div(agent_fx, agent_fy, agent_fz, agent_fscale);
    }

    float minSpeed = 0.5f;
    if (agent_fscale < minSpeed) {
        // Normalise
        vec3Div(agent_fx, agent_fy, agent_fz, agent_fscale);

        // Scale to min
        vec3Mult(agent_fx, agent_fy, agent_fz, minSpeed);
    }

    // Steer away from walls - Computed post normalization to ensure good avoidance. Prevents constant term getting swamped
    const float wallInteractionDistance = 0.10f;
    const float wallSteerStrength = 0.05f;
    const float minPosition = FLAMEGPU->environment.getProperty<float>("MIN_POSITION");
    const float maxPosition = FLAMEGPU->environment.getProperty<float>("MAX_POSITION");

    if (agent_x - minPosition < wallInteractionDistance) {
        agent_fx += wallSteerStrength;
    }
    if (agent_y - minPosition < wallInteractionDistance) {
        agent_fy += wallSteerStrength;
    }
    if (agent_z - minPosition < wallInteractionDistance) {
        agent_fz += wallSteerStrength;
    }

    if (maxPosition - agent_x < wallInteractionDistance) {
        agent_fx -= wallSteerStrength;
    }
    if (maxPosition - agent_y < wallInteractionDistance) {
        agent_fy -= wallSteerStrength;
    }
    if (maxPosition - agent_z < wallInteractionDistance) {
        agent_fz -= wallSteerStrength;
    }

    // Apply the velocity
    const float TIME_SCALE = FLAMEGPU->environment.getProperty<float>("TIME_SCALE");
    agent_x += agent_fx * TIME_SCALE;
    agent_y += agent_fy * TIME_SCALE;
    agent_z += agent_fz * TIME_SCALE;

    // Bound position
    clampPosition(agent_x, agent_y, agent_z, FLAMEGPU->environment.getProperty<float>("MIN_POSITION"), FLAMEGPU->environment.getProperty<float>("MAX_POSITION"));

    // Update global agent memory.
    FLAMEGPU->setVariable<float>("x", agent_x);
    FLAMEGPU->setVariable<float>("y", agent_y);
    FLAMEGPU->setVariable<float>("z", agent_z);

    FLAMEGPU->setVariable<float>("fx", agent_fx);
    FLAMEGPU->setVariable<float>("fy", agent_fy);
    FLAMEGPU->setVariable<float>("fz", agent_fz);

    return flamegpu::ALIVE;
    }
    )###";

typedef struct Experiment { 

    Experiment(std::string title, 
        unsigned int initialPopSize, unsigned int finalPopSize, unsigned int popSizeIncrement, 
        unsigned int initialNumSpecies, unsigned int finalNumSpecies, unsigned int numSpeciesIncrement,
        unsigned int repetitions,
        double targetPopDensity,
        bool spatial,
        unsigned int steps) {
            this->title = title;
            this->initialPopSize = initialPopSize;
            this->finalPopSize = finalPopSize;
            this->popSizeIncrement = popSizeIncrement;
            this->initialNumSpecies = initialNumSpecies;
            this->finalNumSpecies = finalNumSpecies;
            this->numSpeciesIncrement = numSpeciesIncrement;
            this->repetitions = repetitions;
            this->targetPopDensity = targetPopDensity;
            this->spatial = spatial;
            this->steps = steps;
        }
    std::string title;
    unsigned int initialPopSize = 100000;
    unsigned int finalPopSize = 100000;
    unsigned int popSizeIncrement = 100000;
    
    unsigned int initialNumSpecies = 1;
    unsigned int finalNumSpecies = 8;
    unsigned int numSpeciesIncrement = 1;

    unsigned int repetitions = 1;
    double targetPopDensity = 1024;
    bool spatial = true;
    unsigned int steps = 1000;
} Experiment;

int main(int argc, const char ** argv) {

    constexpr unsigned int repetitions = 3;
    Experiment smallFixedPop("Small_Fixed_Pop", 512, 512, 512, 1, 32, 1, repetitions, 1024, true, 1000);
    Experiment smallPops("Small_Pops", 128, 1024, 128, 1, 32, 1, repetitions, 1024, true, 1000);
    Experiment largePops("Large_Pops", 1024, 8192, 1024, 1, 32, 1, repetitions, 1024, true, 1000);
    Experiment deviceMaxed("Device_Maxed", 100000, 100000, 100000, 1, 8, 1, repetitions, 4096, true, 1000);

    Experiment smallFixedPopBruteForce("Small_Fixed_Pop_Brute_Force", 512, 512, 512, 1, 32, 1, repetitions, 1024, false, 1000);
    Experiment smallPopsBruteForce("Small_Pops_Brute_Force", 128, 1024, 128, 1, 32, 1, repetitions, 1024, false, 1000);
    Experiment largePopsBruteForce("Large_Pops_Brute_Force", 1024, 8192, 1024, 1, 32, 1, repetitions, 1024, false, 1000);

    Experiment largePopsFalloff("Large_Pops_Falloff", 2048, 8192, 2048, 1, 127, 8, repetitions, 1024, true, 100);
    Experiment largePopsFalloffBruteForce("Large_Pops_Falloff_Brute_Force", 2048, 8192, 2048, 1, 127, 8, repetitions, 1024, false, 100);

    // std::vector<Experiment> experiments = {largePopsFalloffBruteForce};
    std::vector<Experiment> experiments = {smallFixedPop, smallPops, largePops, deviceMaxed, smallFixedPopBruteForce, smallPopsBruteForce, largePopsBruteForce, largePopsFalloff, largePopsFalloffBruteForce};
    
    for (Experiment experiment : experiments) {
        
        std::cout << std::endl << "Starting experiment: " << experiment.title << std::endl;

        unsigned int initialPopSize = experiment.initialPopSize;
        unsigned int finalPopSize = experiment.finalPopSize;
        unsigned int popSizeIncrement = experiment.popSizeIncrement;
        
        unsigned int initialNumSpecies = experiment.initialNumSpecies;
        unsigned int finalNumSpecies = experiment.finalNumSpecies;
        unsigned int numSpeciesIncrement = experiment.numSpeciesIncrement;

        // Target population density per cubic unit
        double targetPopDensity = experiment.targetPopDensity;

        std::vector<double> serialResults;
        std::vector<double> concurrentResults;
        for (unsigned int popSize = initialPopSize; popSize <= finalPopSize; popSize += popSizeIncrement) {
            for (unsigned int numSpecies = initialNumSpecies; numSpecies <= finalNumSpecies; numSpecies+= numSpeciesIncrement) {
                serialResults.push_back(0.0);
                concurrentResults.push_back(0.0);
            }
        }

        // Pandas
        std::string csvFileName = experiment.title + ".csv";
        std::ofstream csv(csvFileName, std::ios::trunc);
        csv << "is_concurrent,repetition,pop_size,num_species,s_step_mean" << std::endl;
        
        for (unsigned int isConcurrent = 0; isConcurrent <= 1; isConcurrent++) {
            for (unsigned int repetition = 0; repetition < experiment.repetitions; repetition++) {
                unsigned int resultsIndex = 0;
                for (unsigned int popSize = initialPopSize; popSize <= finalPopSize; popSize += popSizeIncrement) {
                    for (unsigned int numSpecies = initialNumSpecies; numSpecies <= finalNumSpecies; numSpecies+= numSpeciesIncrement) {
                        std::cout << "Staring run with popSize: " << popSize << ", species: " << numSpecies << std::endl;
                        flamegpu::ModelDescription model("Boids_Concurrency");

                        /**
                        * GLOBALS
                        */
                        flamegpu::EnvironmentDescription env = model.Environment();
                        std::vector<unsigned int> populationSizes;
                        for (unsigned int pops = 0; pops < numSpecies; pops++) {
                            populationSizes.push_back(popSize);
                        }
                        {                          
                            // Target pop density
                            double targetVolume = (double)popSize / targetPopDensity;
                            double sideLength = std::cbrt(targetVolume);
                            double halfSideLength = sideLength / 2.0;
                            //std::cout << "Using side length: " << sideLength << std::endl;


                            // Environment Bounds
                            env.newProperty("MIN_POSITION", static_cast<float>(-halfSideLength));
                            env.newProperty("MAX_POSITION", static_cast<float>(halfSideLength));

                            // Initialisation parameter(s)
                            env.newProperty("MAX_INITIAL_SPEED", 1.0f);
                            env.newProperty("MIN_INITIAL_SPEED", 0.01f);

                            // Interaction radius
                            env.newProperty("INTERACTION_RADIUS", 0.1f);
                            env.newProperty("SEPARATION_RADIUS", 0.005f);

                            // Global Scalers
                            env.newProperty("TIME_SCALE", 0.0005f);
                            env.newProperty("GLOBAL_SCALE", 0.15f);

                            // Rule scalers
                            env.newProperty("STEER_SCALE", 0.65f);
                            env.newProperty("COLLISION_SCALE", 0.75f);
                            env.newProperty("MATCH_SCALE", 1.25f);
                        }

                        {   // Location message
                            for (unsigned int i = 0; i < populationSizes.size(); i++) {
                                std::string messageName = "location";
                                messageName += std::to_string(i);
                                if (experiment.spatial) {
                                    flamegpu::MessageSpatial3D::Description message = model.newMessage<flamegpu::MessageSpatial3D>(messageName);
                                    // Set the range and bounds.
                                    message.setRadius(env.getProperty<float>("INTERACTION_RADIUS"));
                                    message.setMin(env.getProperty<float>("MIN_POSITION"), env.getProperty<float>("MIN_POSITION"), env.getProperty<float>("MIN_POSITION"));
                                    message.setMax(env.getProperty<float>("MAX_POSITION"), env.getProperty<float>("MAX_POSITION"), env.getProperty<float>("MAX_POSITION"));
                                    // A message to hold the location of an agent.
                                    message.newVariable<int>("id");
                                    // X Y Z are implicit.
                                    // message.newVariable<float>("x");
                                    // message.newVariable<float>("y");
                                    // message.newVariable<float>("z");
                                    message.newVariable<float>("fx");
                                    message.newVariable<float>("fy");
                                    message.newVariable<float>("fz");
                                } else {
                                    flamegpu::MessageBruteForce::Description message = model.newMessage<flamegpu::MessageBruteForce>(messageName);
                                    // A message to hold the location of an agent.
                                    message.newVariable<int>("id");
                                    message.newVariable<float>("x");
                                    message.newVariable<float>("y");
                                    message.newVariable<float>("z");
                                    message.newVariable<float>("fx");
                                    message.newVariable<float>("fy");
                                    message.newVariable<float>("fz");
                                }
                                
                            }
                        }
                        for (unsigned int i = 0; i < populationSizes.size(); i++) {
                            {   // Boid agent
                                std::string agentName("Boid" + std::to_string(i));
                                flamegpu::AgentDescription agent = model.newAgent(agentName);
                                agent.newVariable<int>("id");
                                agent.newVariable<float>("x");
                                agent.newVariable<float>("y");
                                agent.newVariable<float>("z");
                                agent.newVariable<float>("fx");
                                agent.newVariable<float>("fy");
                                agent.newVariable<float>("fz");
                                std::string messageName = "location";
                                messageName += std::to_string(i);
                                std::string outputFuncName = "outputdata";
                                std::string inputFuncName = "inputdata";
                                
                                // Use brute force or spatial?
                                const char* outputFuncSource;
                                const char* inputFuncSource;
                                if (experiment.spatial) {
                                    outputFuncSource = outputdata;
                                    inputFuncSource = inputdata;
                                } else {
                                    outputFuncSource = outputdataBruteForce;
                                    inputFuncSource = inputdataBruteForce;
                                }
                                agent.newRTCFunction(outputFuncName, outputFuncSource).setMessageOutput(messageName);
                                agent.newRTCFunction(inputFuncName, inputFuncSource).setMessageInput(messageName);
                            }
                        }

                        /**
                        * Control flow
                        */     
                        {   // Layer #1
                            flamegpu::LayerDescription layer = model.newLayer();
                            for (unsigned int i = 0; i < populationSizes.size(); i++) {
                                std::string agentName = "Boid";
                                agentName += std::to_string(i);
                                std::string outputFuncName = "outputdata";
                                layer.addAgentFunction(agentName, outputFuncName);
                            }
                        }
                        {   // Layer #2
                            flamegpu::LayerDescription layer = model.newLayer();
                            for (unsigned int i = 0; i < populationSizes.size(); i++) {
                                std::string agentName = "Boid";
                                agentName += std::to_string(i);
                                std::string inputFuncName = "inputdata";
                                layer.addAgentFunction(agentName, inputFuncName);
                            }
                        }


                        /**
                        * Create Model Runner
                        */
                        flamegpu::CUDASimulation simulation(model);

                        /**
                        * Create visualisation
                        */

                        // Initialisation
                        simulation.initialise(argc, argv);
                        // Set the rng seed to be the current repetition. Cannot currently support overriding via cli due to initailise() implementation in alpha.2
                        simulation.SimulationConfig().random_seed = repetition;
                        // Disable telemetry
                        simulation.SimulationConfig().telemetry = false;

                        // If no xml model file was is provided, generate a population.
                        if (simulation.getSimulationConfig().input_file.empty()) {
                            // Set number of steps
                            simulation.SimulationConfig().steps = experiment.steps;

                            // Uniformly distribute agents within space, with uniformly distributed initial velocity.
                            std::mt19937_64 rngEngine(simulation.getSimulationConfig().random_seed);
                            std::uniform_real_distribution<float> position_distribution(env.getProperty<float>("MIN_POSITION"), env.getProperty<float>("MAX_POSITION"));
                            std::uniform_real_distribution<float> velocity_distribution(-1, 1);
                            std::uniform_real_distribution<float> velocity_magnitude_distribution(env.getProperty<float>("MIN_INITIAL_SPEED"), env.getProperty<float>("MAX_INITIAL_SPEED"));
                            
                            unsigned int agentCounter = 0;
                            for (unsigned int i = 0; i < populationSizes.size(); i++) {
                                std::string agentName = "Boid";
                                agentName += std::to_string(i);
                                flamegpu::AgentVector population(model.Agent(agentName), populationSizes[i]);
                                for (unsigned int j = 0; j < populationSizes[i]; j++) {
                                    flamegpu::AgentVector::Agent instance = population[i];
                                    instance.setVariable<int>("id", agentCounter);
                                    agentCounter++;

                                    // Agent position in space
                                    instance.setVariable<float>("x", position_distribution(rngEngine));
                                    instance.setVariable<float>("y", position_distribution(rngEngine));
                                    instance.setVariable<float>("z", position_distribution(rngEngine));

                                    // Generate a random velocity direction
                                    float fx = velocity_distribution(rngEngine);
                                    float fy = velocity_distribution(rngEngine);
                                    float fz = velocity_distribution(rngEngine);
                                    // Generate a random speed between 0 and the maximum initial speed
                                    float fmagnitude = velocity_magnitude_distribution(rngEngine);
                                    // Use the random speed for the velocity.
                                    vec3Normalize(fx, fy, fz);
                                    vec3Mult(fx, fy, fz, fmagnitude);

                                    // Set these for the agent.
                                    instance.setVariable<float>("fx", fx);
                                    instance.setVariable<float>("fy", fy);
                                    instance.setVariable<float>("fz", fz);
                                }
                                simulation.setPopulationData(population);
                            }
                        }

                        /**
                        * Execution
                        */
                        simulation.CUDAConfig().inLayerConcurrency = isConcurrent;
                        //std::cout << "In layer concurrency set to: " << simulation.CUDAConfig().inLayerConcurrency << std::endl;

                        simulation.simulate();
                        const auto runTime = simulation.getElapsedTimeSimulation();
                        const double averageStepTime = runTime / static_cast<double>(experiment.steps);
                        
                        //std::cout << "Run complete. Average step time: " << averageStepTime << "S" << std::endl;
                        if (isConcurrent) {
                            concurrentResults[resultsIndex] += averageStepTime;
                        } else {
                            serialResults[resultsIndex] += averageStepTime;
                        }
                        resultsIndex++;

                        //csv << "is_concurrent,repetition,pop_size,num_species,s_step_mean" << std::endl;
                        csv << isConcurrent << "," << repetition << "," << popSize << "," << numSpecies << "," << averageStepTime << std::endl;
                    }
                }
            }
        }
    }
    return 0;
}


