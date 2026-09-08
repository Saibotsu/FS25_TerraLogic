-- TerraLogic Phase 1 soil profiles.
-- Values are normalized: compaction/roughness 0=low, 1=high;
-- aggregateSize 0=coarse clods, 0.50=crumbly seedbed,
-- 1=over-fine or structureless (dry powder / wet smear). Surface compaction
-- and roughness distinguish those two physically different bad states.
-- Every pass approaches a target by strength. This makes repeated work
-- converge and prevents unbounded numerical drift.
-- `overspeed.strengthScale` is the fraction of the normal pass strength left
-- at maximum soil overspeed. `overspeed.effects` adds class-specific physical
-- consequences after that weakened pass. Those overspeed rules remain
-- independent from Work Quality. The separate SUITABILITY table at the end
-- evaluates the pre-pass soil for class-specific quality and dropout effects.

-- Seeder levelling targets and their dropout-free roughness limits share one
-- definition so later balancing cannot make a drill converge to a seedbed
-- rougher than the same class accepts at rated/shop speed. Stored roughness is
-- the inverse of displayed Evenness: these targets equal 90%, 94% and 84%
-- Evenness and all retain a quantization-safe margin below their limit.
local SEEDER_ROUGHNESS = {
    sowingMachine={target=0.10, dropoutFreeMaximum=0.26},
    precisionPlanter={target=0.06, dropoutFreeMaximum=0.22},
    directDrill={target=0.16, dropoutFreeMaximum=0.30},
    precisionDirectDrill={target=0.10, dropoutFreeMaximum=0.25}
}

TerraLogicSoilProfiles = {
    DEFAULTS = {
        surfaceCompaction = 0.42,
        deepCompaction = 0.25,
        aggregateSize = 0.50,
        roughness = 0.25,
        -- Slow biological memory. Its main effect remains susceptibility to
        -- later traffic; the unified harvest assessment also gives very low
        -- resilience a small cost and healthy long-term management headroom.
        resilience = 0.50
    },

    -- Direct root-zone yield response. Ordinary, competently cultivated
    -- topsoil (the normal cultivator target) is root-yield-neutral. Ploughing
    -- creates a visible physical reserve, while the unified harvest assessment
    -- rewards the complete managed system rather than loose soil by itself.
    -- Convex curves keep the initialized/acceptable condition inexpensive,
    -- while widespread severe wheel damage becomes economically meaningful.
    -- The combined theoretical extreme is about 35%, inside the 6-34% range
    -- reported by the 2021 traffic-compaction meta-analysis (isolated field
    -- experiments can be more severe). Sparse tramlines remain area-weighted.
    ROOT_YIELD = {
        surfaceCompaction = {good=0.30, maximumLoss=0.15, exponent=1.40},
        deepCompaction = {good=0.10, maximumLoss=0.26, exponent=1.45}
    },

    -- PF texture changes how quickly a pass reaches its target, not what the
    -- HUD calls ideal. The normalized optimum therefore remains 50% tilth and
    -- high structural quality on every soil. Coarse soils crumble and level
    -- readily but are easy to overwork; fine silty clay needs more energetic
    -- passes and remains cloddier, while rolling compacts it more strongly.
    -- Class overrides replace the corresponding default layer response.
    PF_SOIL_RESPONSES = {
        [1] = { -- Loamy Sand
            name="Loamy Sand",
            strength={surfaceCompaction=0.90, deepCompaction=0.82,
                aggregateSize=1.12, roughness=1.08},
            classes={
                plow={targetOffset={aggregateSize=0.04, roughness=-0.05}},
                subsoiler={strength={deepCompaction=0.78}},
                cultivator={strength={aggregateSize=1.15},
                    targetOffset={aggregateSize=0.04}},
                shallowCultivator={strength={aggregateSize=1.18},
                    targetOffset={aggregateSize=0.04}},
                discHarrow={strength={aggregateSize=1.18},
                    targetOffset={aggregateSize=0.05}},
                powerHarrow={strength={aggregateSize=1.15},
                    targetOffset={aggregateSize=0.06}},
                roller={strength={surfaceCompaction=0.88,
                    aggregateSize=1.05}}
            }
        },
        [2] = { -- Sandy Loam: neutral reference texture
            name="Sandy Loam",
            strength={surfaceCompaction=1.00, deepCompaction=1.00,
                aggregateSize=1.00, roughness=1.00},
            classes={}
        },
        [3] = { -- Loam
            name="Loam",
            strength={surfaceCompaction=0.95, deepCompaction=0.93,
                aggregateSize=0.94, roughness=0.96},
            classes={
                plow={targetOffset={aggregateSize=-0.02, roughness=0.02}},
                powerHarrow={strength={aggregateSize=1.00}},
                roller={strength={surfaceCompaction=1.05}}
            }
        },
        [4] = { -- Silty Clay
            name="Silty Clay",
            strength={surfaceCompaction=0.82, deepCompaction=0.78,
                aggregateSize=0.72, roughness=0.84},
            classes={
                plow={strength={aggregateSize=0.90, roughness=0.95},
                    targetOffset={aggregateSize=-0.06, roughness=0.07}},
                subsoiler={strength={deepCompaction=0.84}},
                spader={strength={aggregateSize=0.82, roughness=0.90}},
                cultivator={strength={aggregateSize=0.65},
                    targetOffset={aggregateSize=-0.05}},
                shallowCultivator={strength={aggregateSize=0.62},
                    targetOffset={aggregateSize=-0.06}},
                discHarrow={strength={aggregateSize=0.72},
                    targetOffset={aggregateSize=-0.04}},
                powerHarrow={strength={aggregateSize=0.90},
                    targetOffset={aggregateSize=-0.02}},
                roller={strength={surfaceCompaction=1.18,
                    aggregateSize=0.85, roughness=0.88},
                    targetOffset={surfaceCompaction=0.04}}
            }
        }
    },

    -- At equal contact pressure and axle load, cohesive fine soil is more
    -- vulnerable in the moisture-agnostic game model; coarse soil dissipates
    -- the same pass somewhat better. These modest factors avoid replacing the
    -- much stronger tyre-pressure and axle-load calculations.
    PF_TRAFFIC_RESPONSES = {
        [1]={surface=0.88, deep=0.82},
        [2]={surface=1.00, deep=1.00},
        [3]={surface=1.05, deep=1.04},
        [4]={surface=1.15, deep=1.12}
    },

    -- Rolling after sowing can improve seed-to-soil contact and close shallow
    -- slots, but it cannot replace seed that was never placed.  TerraLogic
    -- therefore records only the seed-quality loss caused by roller-correctable
    -- seedbed states (loose, coarse or rough).  A later successful soil-roller
    -- pass may recover this share; speed, wear and physical seed gaps remain.
    ROLLER_SEED_RESCUE = {
        -- Strong enough to matter beyond Vanilla's 2.5% bonus, but still
        -- limited to seedbed/contact loss: missing seed, wear and overspeed
        -- placement errors remain irreversible.
        maximumRecoverableShare = 0.82,
        maximumQualityGain = 0.18,
        textureEffectiveness = {
            [1]=0.82, -- Loamy Sand: contact improves, but consolidation is weaker
            [2]=1.00, -- Sandy Loam reference
            [3]=1.05, -- Loam responds well at suitable moisture
            [4]=0.90  -- Silty Clay: useful, with a moisture-agnostic safety discount
        }
    },

    PROFILES = {
        plow = {
            -- Small transition-horizon contribution in the combined deep
            -- index, not a substitute for true subsoiling. Cap a full pass.
            deepCompaction = {target=0.30, strength=0.05,
                maxDelta=0.015, mode="reduceOnly"},
            surfaceCompaction = {target=0.14, strength=0.78,
                mode="reduceOnly"},
            aggregateSize = {target=0.12, strength=0.72,
                mode="reduceOnly"},
            roughness = {target=0.84, strength=0.82,
                mode="increaseOnly"},
            overspeed = {
                -- At extreme speed the body still disturbs the surface, but
                -- it no longer completes a controlled full-depth loosening
                -- and inversion. The stronger separation is intentional:
                -- 25 km/h must not resemble the rated 8 km/h pass.
                strengthScale = {
                    surfaceCompaction=0.15, deepCompaction=0.15,
                    aggregateSize=0.45, roughness=0.35
                },
                effects = {
                    aggregateSize = {target=0.90, strength=0.74, mode="increaseOnly"},
                    roughness = {target=0.99, strength=0.86, mode="increaseOnly"}
                },
                -- The former world-grid variation produced a conspicuous
                -- repeating sawtooth pattern even during ordinary shop-speed
                -- work. Keep only the continuous mean overspeed response.
                effectSeverityExponent = 0.70
            }
        },
        subsoiler = {
            surfaceCompaction = {target=0.24, strength=0.40,
                mode="reduceOnly"},
            deepCompaction = {target=0.10, strength=0.72, mode="reduceOnly"},
            -- A subsoiler can fracture coarse material lifted by its shanks,
            -- but it cannot rebuild aggregates from an over-fine topsoil.
            aggregateSize = {target=0.25, strength=0.36,
                mode="increaseOnly"},
            roughness = {target=0.54, strength=0.46},
            overspeed = {
                strengthScale = {
                    surfaceCompaction=0.70, deepCompaction=0.55,
                    aggregateSize=0.75, roughness=0.65
                },
                effects = {
                    aggregateSize = {target=0.62, strength=0.10, mode="increaseOnly"},
                    roughness = {target=0.78, strength=0.22, mode="increaseOnly"}
                }
            }
        },
        spader = {
            surfaceCompaction = {target=0.18, strength=0.70,
                mode="reduceOnly"},
            deepCompaction = {target=0.16, strength=0.28, mode="reduceOnly"},
            aggregateSize = {target=0.47, strength=0.64},
            roughness = {target=0.38, strength=0.64},
            overspeed = {
                strengthScale = {
                    surfaceCompaction=0.65, deepCompaction=0.55,
                    aggregateSize=0.45, roughness=0.50
                },
                effects = {
                    roughness = {target=0.68, strength=0.20, mode="increaseOnly"}
                }
            }
        },
        cultivator = {
            -- The implement loosens the worked surface. Any reconsolidation
            -- from tractor wheels or a separate packer is recorded by those
            -- contacts instead of being hidden in the full-width tool pass.
            surfaceCompaction = {target=0.30, strength=0.46,
                mode="reduceOnly"},
            -- One ordinary pass per crop cycle must not inevitably
            -- pulverize an otherwise healthy seedbed. Repeated work still
            -- converges on the fine side of optimum, while discs, powered
            -- tools and overspeed retain the stronger overworking risk.
            aggregateSize = {target=0.62, strength=0.40,
                mode="increaseOnly"},
            roughness = {target=0.16, strength=0.90},
            overspeed = {
                strengthScale = {
                    surfaceCompaction=0.65, aggregateSize=0.85,
                    roughness=0.60
                },
                effects = {
                    aggregateSize = {target=0.96, strength=0.22, mode="increaseOnly"},
                    roughness = {target=0.52, strength=0.16, mode="increaseOnly"}
                }
            }
        },
        shallowCultivator = {
            surfaceCompaction = {target=0.38, strength=0.30,
                mode="reduceOnly"},
            aggregateSize = {target=0.62, strength=0.34,
                mode="increaseOnly"},
            roughness = {target=0.12, strength=0.88},
            overspeed = {
                strengthScale = {
                    surfaceCompaction=0.70, aggregateSize=0.85,
                    roughness=0.60
                },
                effects = {
                    aggregateSize = {target=0.96, strength=0.25, mode="increaseOnly"},
                    roughness = {target=0.48, strength=0.14, mode="increaseOnly"}
                }
            }
        },
        discHarrow = {
            surfaceCompaction = {target=0.36, strength=0.34,
                mode="reduceOnly"},
            aggregateSize = {target=0.68, strength=0.38,
                mode="increaseOnly"},
            roughness = {target=0.14, strength=0.86},
            overspeed = {
                strengthScale = {
                    surfaceCompaction=0.75, aggregateSize=0.95,
                    -- A faster pass provides fewer useful levelling contacts.
                    -- It must not make the disc harrow look more precise just
                    -- because the discs skim across the high spots.
                    roughness=0.42
                },
                effects = {
                    aggregateSize = {target=0.98, strength=0.28, mode="increaseOnly"},
                    -- Severe speed leaves a mildly irregular finish. Tilth is
                    -- still the stronger failure channel, but Evenness can no
                    -- longer improve beyond the normal pass at overspeed.
                    roughness = {target=0.36, strength=0.16, mode="increaseOnly"}
                }
            }
        },
        powerHarrow = {
            surfaceCompaction = {target=0.34, strength=0.30,
                mode="reduceOnly"},
            -- One competent pass creates a fine but still structured seedbed.
            -- The old 0.76 target made rated work unnecessarily pulverizing
            -- and could make a weakened overspeed pass look beneficial.
            aggregateSize = {target=0.62, strength=0.45,
                mode="increaseOnly"},
            roughness = {target=0.06, strength=0.82},
            overspeed = {
                strengthScale = {
                    surfaceCompaction=0.75, aggregateSize=0.45,
                    roughness=0.55
                },
                effects = {
                    -- Fewer rotor contacts per square metre already follow
                    -- from the weakened normal pass above. Overspeed must not
                    -- actively turn pulverized soil back into large clods.
                    roughness = {target=0.42, strength=0.18, mode="increaseOnly"}
                }
            }
        },
        roller = {
            -- Consolidate loose soil, never "loosen" an already compacted
            -- seedbed by converging backwards from a high value.
            surfaceCompaction = {target=0.48, strength=0.60,
                mode="increaseOnly"},
            -- Rollers crush exposed clods only where they make contact. They
            -- mainly consolidate and level; they must not substitute for a
            -- cultivator or powered seedbed pass.
            aggregateSize = {target=0.54, strength=0.18,
                mode="increaseOnly"},
            roughness = {target=0.04, strength=0.84, mode="reduceOnly"},
            overspeed = {
                strengthScale = {
                    surfaceCompaction=0.45, aggregateSize=0.50,
                    roughness=0.35
                },
                effects = {
                    roughness = {target=0.30, strength=0.12, mode="increaseOnly"}
                }
            }
        },
        -- Seeder effects are full-width area averages. Conventional drills
        -- commonly finish with a covering/levelling harrow and therefore
        -- smooth a rough seedbed noticeably. Planter row units and their
        -- closing wheels only affect narrow strips. No-till openers tolerate
        -- rougher ground but create only a local mini seedbed; that tolerance
        -- remains separate in the suitability profiles below.
        -- Aggregate effects stay deliberately small: seeders may break a few
        -- coarse clods, but cannot replace seedbed cultivation.
        sowingMachine = {
            surfaceCompaction = {target=0.46, strength=0.08,
                mode="increaseOnly"},
            aggregateSize = {target=0.50, strength=0.035,
                mode="increaseOnly"},
            roughness = {target=SEEDER_ROUGHNESS.sowingMachine.target,
                strength=0.18},
            overspeed = {
                strengthScale = {surfaceCompaction=0.45,
                    aggregateSize=0.55, roughness=0.40},
                effects = {
                    aggregateSize = {target=0.72, strength=0.04,
                        mode="increaseOnly"},
                    roughness = {target=0.32, strength=0.08, mode="increaseOnly"}
                }
            }
        },
        precisionPlanter = {
            surfaceCompaction = {target=0.48, strength=0.10,
                mode="increaseOnly"},
            aggregateSize = {target=0.50, strength=0.025,
                mode="increaseOnly"},
            roughness = {target=SEEDER_ROUGHNESS.precisionPlanter.target,
                strength=0.04},
            overspeed = {
                strengthScale = {surfaceCompaction=0.40,
                    aggregateSize=0.50, roughness=0.35},
                effects = {
                    aggregateSize = {target=0.70, strength=0.035,
                        mode="increaseOnly"},
                    roughness = {target=0.38, strength=0.10, mode="increaseOnly"}
                }
            }
        },
        directDrill = {
            surfaceCompaction = {target=0.45, strength=0.06,
                mode="increaseOnly"},
            aggregateSize = {target=0.50, strength=0.015,
                mode="increaseOnly"},
            roughness = {target=SEEDER_ROUGHNESS.directDrill.target,
                strength=0.10},
            overspeed = {
                strengthScale = {surfaceCompaction=0.50,
                    aggregateSize=0.55, roughness=0.45},
                effects = {
                    aggregateSize = {target=0.68, strength=0.025,
                        mode="increaseOnly"},
                    roughness = {target=0.30, strength=0.07, mode="increaseOnly"}
                }
            }
        },
        -- Narrow V-discs open only a small share of the full working width.
        -- The profile therefore records a subtle slit/closure effect rather
        -- than pretending that a grassland injector cultivates the surface.
        slurryInjector = {
            surfaceCompaction = {target=0.36, strength=0.025,
                mode="reduceOnly"},
            aggregateSize = {target=0.50, strength=0.008,
                mode="increaseOnly"},
            -- Narrow slots can close a rough surface or leave a subtle line
            -- in a smooth one. Keep this bidirectional response tiny because
            -- only a small share of the full width is opened.
            roughness = {target=0.20, strength=0.020},
            overspeed = {
                strengthScale = {surfaceCompaction=0.45,
                    aggregateSize=0.40, roughness=0.35},
                effects = {
                    roughness = {target=0.32, strength=0.045,
                        mode="increaseOnly"}
                }
            }
        },
        precisionDirectDrill = {
            surfaceCompaction = {target=0.47, strength=0.08,
                mode="increaseOnly"},
            aggregateSize = {target=0.50, strength=0.020,
                mode="increaseOnly"},
            roughness = {target=SEEDER_ROUGHNESS.precisionDirectDrill.target,
                strength=0.055},
            overspeed = {
                strengthScale = {surfaceCompaction=0.45,
                    aggregateSize=0.52, roughness=0.40},
                effects = {
                    aggregateSize = {target=0.70, strength=0.030,
                        mode="increaseOnly"},
                    roughness = {target=0.34, strength=0.085,
                        mode="increaseOnly"}
                }
            }
        },
        -- A crop-residue mulcher does not perform full-width mineral-soil
        -- tillage. Residue and resilience effects are handled separately;
        -- tyres still compact the field through the traffic model.
        mulcher = {},
        weeder = {
            surfaceCompaction = {target=0.38, strength=0.06,
                mode="reduceOnly"},
            aggregateSize = {target=0.60, strength=0.06,
                mode="increaseOnly"},
            roughness = {target=0.18, strength=0.06},
            overspeed = {
                strengthScale = {
                    surfaceCompaction=0.60, aggregateSize=0.65,
                    roughness=0.45
                },
                effects = {
                    aggregateSize = {target=0.78, strength=0.10, mode="increaseOnly"},
                    roughness = {target=0.42, strength=0.14, mode="increaseOnly"}
                }
            }
        },
        hoe = {
            surfaceCompaction = {target=0.34, strength=0.10,
                mode="reduceOnly"},
            aggregateSize = {target=0.62, strength=0.10,
                mode="increaseOnly"},
            roughness = {target=0.20, strength=0.08},
            overspeed = {
                strengthScale = {
                    surfaceCompaction=0.55, aggregateSize=0.65,
                    roughness=0.45
                },
                effects = {
                    aggregateSize = {target=0.82, strength=0.14, mode="increaseOnly"},
                    roughness = {target=0.50, strength=0.18, mode="increaseOnly"}
                }
            }
        },
        stonePicker = {
            surfaceCompaction = {target=0.36, strength=0.10,
                mode="reduceOnly"},
            aggregateSize = {target=0.48, strength=0.08,
                mode="increaseOnly"},
            roughness = {target=0.28, strength=0.10},
            overspeed = {
                strengthScale = {
                    surfaceCompaction=0.45, aggregateSize=0.45,
                    roughness=0.40
                },
                effects = {
                    roughness = {target=0.42, strength=0.12, mode="increaseOnly"}
                }
            }
        }
    },

    -- Input-soil suitability is deliberately separate from the physical
    -- pass targets above.  `qualityFloor` limits the invisible Work Quality
    -- consequence at the worst possible soil state.  `dropoutMax` limits the
    -- independently visible failed-area share.  A factor may contribute to
    -- Work Quality (`qualityWeight`), physical dropouts (`dropoutWeight`), or
    -- both.  This prevents one generic "bad soil" number from treating a
    -- subsoiler like a precision planter.
    --
    -- Stored values: compaction/roughness 0=low, 1=high; aggregateSize
    -- 0=coarse, 0.50=crumb, 1=over-fine.  Band factors therefore retain the
    -- agronomically useful middle range without changing the global HUD.
    SUITABILITY = {
        plow = {
            qualityFloor=0.82,
            factors={
                surfaceCompaction={shape="low", good=0.45, bad=1.00, qualityWeight=2},
                deepCompaction={shape="low", good=0.35, bad=0.95, qualityWeight=1},
                aggregateSize={shape="band", target=0.50, goodRadius=0.30, badRadius=0.50, qualityWeight=0.5},
                roughness={shape="low", good=0.65, bad=1.00, qualityWeight=0.5}
            }
        },
        subsoiler = {
            qualityFloor=0.78,
            factors={
                surfaceCompaction={shape="low", good=0.55, bad=1.00, qualityWeight=1},
                deepCompaction={shape="low", good=0.28, bad=0.95, qualityWeight=4},
                roughness={shape="low", good=0.70, bad=1.00, qualityWeight=0.5}
            }
        },
        cultivator = {
            qualityFloor=0.76,
            factors={
                surfaceCompaction={shape="low", good=0.38, bad=0.95, qualityWeight=2},
                aggregateSize={shape="band", target=0.50, goodRadius=0.24, badRadius=0.50, qualityWeight=3},
                roughness={shape="low", good=0.42, bad=0.95, qualityWeight=2}
            }
        },
        shallowCultivator = {
            qualityFloor=0.78,
            factors={
                surfaceCompaction={shape="low", good=0.42, bad=0.95, qualityWeight=1},
                aggregateSize={shape="band", target=0.50, goodRadius=0.25, badRadius=0.50, qualityWeight=2},
                roughness={shape="low", good=0.38, bad=0.90, qualityWeight=2}
            }
        },
        discHarrow = {
            qualityFloor=0.76,
            factors={
                surfaceCompaction={shape="low", good=0.42, bad=0.95, qualityWeight=1},
                aggregateSize={shape="band", target=0.50, goodRadius=0.24, badRadius=0.50, qualityWeight=2},
                roughness={shape="low", good=0.38, bad=0.90, qualityWeight=2}
            }
        },
        powerHarrow = {
            qualityFloor=0.72,
            factors={
                surfaceCompaction={shape="low", good=0.45, bad=0.95, qualityWeight=1},
                aggregateSize={shape="band", target=0.50, goodRadius=0.20, badRadius=0.50, qualityWeight=3},
                roughness={shape="low", good=0.30, bad=0.88, qualityWeight=3}
            }
        },
        spader = {
            qualityFloor=0.76,
            factors={
                surfaceCompaction={shape="low", good=0.42, bad=0.98, qualityWeight=2},
                deepCompaction={shape="low", good=0.35, bad=0.95, qualityWeight=1},
                aggregateSize={shape="band", target=0.50, goodRadius=0.24, badRadius=0.50, qualityWeight=3},
                roughness={shape="low", good=0.45, bad=0.95, qualityWeight=2}
            }
        },
        roller = {
            qualityFloor=0.78,
            factors={
                surfaceCompaction={shape="band", target=0.42, goodRadius=0.28, badRadius=0.58, qualityWeight=2},
                aggregateSize={shape="band", target=0.50, goodRadius=0.30, badRadius=0.50, qualityWeight=1},
                roughness={shape="low", good=0.45, bad=1.00, qualityWeight=3}
            }
        },
        sowingMachine = {
            qualityFloor=0.58, dropoutMax=0.20, dropoutOnset=0.13,
            residualQualityShare=0.62,
            safeSpeedMinimumRatio=0.58, slowQualityRecovery=0.45,
            dropoutSpeedWindowRatio=0.32,
            factors={
                surfaceCompaction={shape="band", target=0.42, goodRadius=0.13, badRadius=0.48, qualityWeight=2, dropoutWeight=2},
                aggregateSize={shape="band", target=0.50, goodRadius=0.15, badRadius=0.50, qualityWeight=3, dropoutWeight=2},
                roughness={shape="low", good=SEEDER_ROUGHNESS.sowingMachine.dropoutFreeMaximum, bad=0.80, qualityWeight=3, dropoutWeight=4}
            }
        },
        directDrill = {
            qualityFloor=0.70, dropoutMax=0.10, dropoutOnset=0.18,
            residualQualityShare=0.58,
            safeSpeedMinimumRatio=0.72, slowQualityRecovery=0.40,
            dropoutSpeedWindowRatio=0.35,
            factors={
                surfaceCompaction={shape="band", target=0.44, goodRadius=0.22, badRadius=0.56, qualityWeight=3, dropoutWeight=2},
                aggregateSize={shape="band", target=0.50, goodRadius=0.30, badRadius=0.50, qualityWeight=1, dropoutWeight=1},
                roughness={shape="low", good=SEEDER_ROUGHNESS.directDrill.dropoutFreeMaximum, bad=0.90, qualityWeight=2, dropoutWeight=3}
            }
        },
        precisionPlanter = {
            qualityFloor=0.52, dropoutMax=0.25, dropoutOnset=0.16,
            residualQualityShare=0.66,
            safeSpeedMinimumRatio=0.55, slowQualityRecovery=0.35,
            dropoutSpeedWindowRatio=0.28,
            factors={
                surfaceCompaction={shape="band", target=0.43, goodRadius=0.13, badRadius=0.45, qualityWeight=2, dropoutWeight=2},
                aggregateSize={shape="band", target=0.50, goodRadius=0.16, badRadius=0.48, qualityWeight=3, dropoutWeight=2},
                roughness={shape="low", good=SEEDER_ROUGHNESS.precisionPlanter.dropoutFreeMaximum, bad=0.70, qualityWeight=4, dropoutWeight=5}
            }
        },
        precisionDirectDrill = {
            qualityFloor=0.60, dropoutMax=0.17, dropoutOnset=0.14,
            residualQualityShare=0.63,
            safeSpeedMinimumRatio=0.63, slowQualityRecovery=0.38,
            dropoutSpeedWindowRatio=0.31,
            factors={
                surfaceCompaction={shape="band", target=0.44,
                    goodRadius=0.16, badRadius=0.50,
                    qualityWeight=3, dropoutWeight=2},
                aggregateSize={shape="band", target=0.50,
                    goodRadius=0.20, badRadius=0.50,
                    qualityWeight=2, dropoutWeight=1},
                roughness={shape="low",
                    good=SEEDER_ROUGHNESS.precisionDirectDrill.dropoutFreeMaximum,
                    bad=0.80, qualityWeight=3, dropoutWeight=4}
            }
        },
        mulcher = {
            qualityFloor=0.88, dropoutMax=0.05, dropoutOnset=0.35,
            residualQualityShare=0.65,
            factors={roughness={shape="low", good=0.42, bad=0.95, qualityWeight=1, dropoutWeight=1}}
        },
        stonePicker = {
            qualityFloor=0.80, dropoutMax=0.10, dropoutOnset=0.22,
            residualQualityShare=0.55,
            factors={
                surfaceCompaction={shape="low", good=0.48, bad=0.98, qualityWeight=1, dropoutWeight=1},
                aggregateSize={shape="band", target=0.50, goodRadius=0.25, badRadius=0.50, qualityWeight=1, dropoutWeight=1},
                roughness={shape="low", good=0.24, bad=0.88, qualityWeight=2, dropoutWeight=3}
            }
        },
        hoe = {
            qualityFloor=0.72, dropoutMax=0.15, dropoutOnset=0.18,
            residualQualityShare=0.55,
            factors={
                surfaceCompaction={shape="low", good=0.40, bad=0.92, qualityWeight=2, dropoutWeight=1},
                aggregateSize={shape="band", target=0.50, goodRadius=0.22, badRadius=0.50, qualityWeight=2, dropoutWeight=1},
                roughness={shape="low", good=0.20, bad=0.78, qualityWeight=2, dropoutWeight=3}
            }
        },
        weeder = {
            qualityFloor=0.78, dropoutMax=0.12, dropoutOnset=0.22,
            residualQualityShare=0.55,
            factors={
                surfaceCompaction={shape="low", good=0.44, bad=0.95, qualityWeight=2, dropoutWeight=1},
                aggregateSize={shape="band", target=0.50, goodRadius=0.25, badRadius=0.50, qualityWeight=1, dropoutWeight=1},
                roughness={shape="low", good=0.18, bad=0.75, qualityWeight=2, dropoutWeight=3}
            }
        },
        mower = {
            qualityFloor=0.76, dropoutMax=0.12, dropoutOnset=0.18,
            residualQualityShare=0.55,
            factors={roughness={shape="low", good=0.14, bad=0.78, qualityWeight=1, dropoutWeight=1}}
        },
        windrower = {
            qualityFloor=0.82, dropoutMax=0.08, dropoutOnset=0.22,
            residualQualityShare=0.55,
            factors={roughness={shape="low", good=0.18, bad=0.82, qualityWeight=1, dropoutWeight=1}}
        },
        tedder = {
            qualityFloor=0.84, dropoutMax=0.07, dropoutOnset=0.25,
            residualQualityShare=0.55,
            factors={roughness={shape="low", good=0.20, bad=0.85, qualityWeight=1, dropoutWeight=1}}
        },
        baler = {
            qualityFloor=0.86, dropoutMax=0.07, dropoutOnset=0.25,
            residualQualityShare=0.50,
            factors={roughness={shape="low", good=0.18, bad=0.82, qualityWeight=1, dropoutWeight=1}}
        },
        loaderWagon = {
            qualityFloor=0.86, dropoutMax=0.07, dropoutOnset=0.25,
            residualQualityShare=0.50,
            factors={roughness={shape="low", good=0.18, bad=0.82, qualityWeight=1, dropoutWeight=1}}
        },
        liquidSprayer = {
            qualityFloor=0.88, dropoutMax=0.05, dropoutOnset=0.30,
            residualQualityShare=0.60,
            -- No invisible boom-motion penalty from the abstract soil map.
            -- Rain and speed effects are separate QualityManager mechanisms.
            factors={}
        },
        fertilizerSpreader = {
            qualityFloor=0.90, dropoutMax=0.04, dropoutOnset=0.35,
            residualQualityShare=0.60,
            factors={roughness={shape="low", good=0.28, bad=0.95, qualityWeight=1, dropoutWeight=1}}
        },
        manureSpreader = {
            qualityFloor=0.92, dropoutMax=0.03, dropoutOnset=0.40,
            residualQualityShare=0.60,
            factors={roughness={shape="low", good=0.32, bad=0.98, qualityWeight=1, dropoutWeight=1}}
        },
        slurrySpreader = {
            qualityFloor=0.92, dropoutMax=0.03, dropoutOnset=0.40,
            residualQualityShare=0.60,
            factors={roughness={shape="low", good=0.32, bad=0.98, qualityWeight=1, dropoutWeight=1}}
        },
        slurryApplicator = {
            qualityFloor=0.84, dropoutMax=0.06, dropoutOnset=0.28,
            residualQualityShare=0.60,
            factors={roughness={shape="low", good=0.24, bad=0.90, qualityWeight=1, dropoutWeight=1}}
        },
        slurryInjector = {
            qualityFloor=0.84, dropoutMax=0.06, dropoutOnset=0.28,
            residualQualityShare=0.60,
            factors={
                surfaceCompaction={shape="low", good=0.58, bad=0.98,
                    qualityWeight=1, dropoutWeight=1},
                roughness={shape="low", good=0.24, bad=0.90,
                    qualityWeight=1, dropoutWeight=1}
            }
        }
    }
}

function TerraLogicSoilProfiles:getProfile(classKey)
    return self.PROFILES[classKey]
end

function TerraLogicSoilProfiles:getSuitabilityProfile(classKey)
    return self.SUITABILITY[classKey]
end

function TerraLogicSoilProfiles:getPFSoilResponse(soilTypeIndex, classKey)
    self.pfSoilResponseCache = self.pfSoilResponseCache or {}
    local cacheKey = tostring(soilTypeIndex or "none") .. ":"
        .. tostring(classKey or "none")
    local cached = self.pfSoilResponseCache[cacheKey]
    if cached ~= nil then return cached ~= false and cached or nil end
    local soil = self.PF_SOIL_RESPONSES[tonumber(soilTypeIndex)]
    if soil == nil then
        self.pfSoilResponseCache[cacheKey] = false
        return nil
    end
    local class = soil.classes ~= nil and soil.classes[classKey] or nil
    local response = {name=soil.name, strength={}, targetOffset={}}
    for layerId, value in pairs(soil.strength or {}) do
        response.strength[layerId] = value
    end
    for layerId, value in pairs(soil.targetOffset or {}) do
        response.targetOffset[layerId] = value
    end
    if class ~= nil then
        for layerId, value in pairs(class.strength or {}) do
            response.strength[layerId] = value
        end
        for layerId, value in pairs(class.targetOffset or {}) do
            response.targetOffset[layerId] = value
        end
    end
    -- These response definitions are immutable balance data. Reusing the
    -- merged table avoids allocating two nested tables for every affected
    -- raster cell while preserving exactly the same values.
    self.pfSoilResponseCache[cacheKey] = response
    return response
end

function TerraLogicSoilProfiles:getPFTrafficResponse(soilTypeIndex)
    return self.PF_TRAFFIC_RESPONSES[tonumber(soilTypeIndex)]
end

local function rescueRamp(value, onset, full)
    local t = math.clamp(((tonumber(value) or 0) - onset)
        / math.max(full - onset, 0.0001), 0, 1)
    return t * t * (3 - 2 * t)
end

-- Returns the fraction of a seedbed-caused quality loss that a roller can
-- plausibly address. Roughness is the strongest signal, followed by excessive
-- looseness and coarse clods. Over-fine or already dense soil deliberately
-- creates no rescue potential: rolling cannot reverse either condition.
function TerraLogicSoilProfiles:getRollerSeedRescuePotential(
        state, soilTypeIndex)
    if state == nil then return 0 end
    local surface = math.clamp(tonumber(state.surfaceCompaction) or 0.42, 0, 1)
    local aggregate = math.clamp(tonumber(state.aggregateSize) or 0.50, 0, 1)
    local roughness = math.clamp(tonumber(state.roughness) or 0.25, 0, 1)
    local looseNeed = rescueRamp(0.42 - surface, 0.02, 0.30)
    local coarseNeed = rescueRamp(0.50 - aggregate, 0.03, 0.38)
    local roughNeed = rescueRamp(roughness, 0.12, 0.68)
    local correctableNeed = math.clamp(
        0.35 * looseNeed + 0.20 * coarseNeed + 0.45 * roughNeed,
        0,
        1
    )
    -- Dense and pulverized seedbeds are not roller-repairable. Fade the
    -- potential before those states can turn rolling into a universal cure.
    local denseBlock = rescueRamp(surface, 0.54, 0.82)
    local fineBlock = rescueRamp(aggregate, 0.66, 0.92)
    local texture = self.ROLLER_SEED_RESCUE.textureEffectiveness[
        tonumber(soilTypeIndex)] or 1
    return math.clamp(correctableNeed
        * (1 - denseBlock) * (1 - fineBlock) * texture, 0, 1)
end

function TerraLogicSoilProfiles:getRollerSeedRescueLimits()
    return self.ROLLER_SEED_RESCUE.maximumRecoverableShare or 0,
        self.ROLLER_SEED_RESCUE.maximumQualityGain or 0
end

-- A field roller is carried by continuous ground contact rather than by a
-- cutting depth. On a rough surface it begins to unload and re-contact sooner
-- as speed rises; on an even surface it tolerates somewhat more speed. This
-- shared factor drives both physical soil response and post-sowing seed-contact
-- rescue so the two systems cannot drift apart during later balancing.
function TerraLogicSoilProfiles:getRollerContactEfficiency(
        state, speedKph, shopSpeedKph)
    local roughness = math.clamp(
        tonumber(state ~= nil and state.roughness) or 0.25, 0, 1)
    local evenness = 1 - roughness
    local toleranceT = math.clamp((evenness - 0.25) / 0.60, 0, 1)
    toleranceT = toleranceT * toleranceT * (3 - 2 * toleranceT)

    local shop = math.max(tonumber(shopSpeedKph) or 0, 0.01)
    local ratio = math.max(tonumber(speedKph) or 0, 0) / shop
    local atShop = 0.95 + 0.05 * toleranceT
    local at125 = 0.65 + 0.20 * toleranceT
    local at150 = 0.30 + 0.25 * toleranceT
    local at200 = 0.03 + 0.05 * toleranceT

    if ratio <= 0.85 then return 1 end
    local function blend(a, b, t)
        t = math.clamp(t, 0, 1)
        t = t * t * (3 - 2 * t)
        return a + (b - a) * t
    end
    if ratio <= 1 then
        return blend(1, atShop, (ratio - 0.85) / 0.15)
    elseif ratio <= 1.25 then
        return blend(atShop, at125, (ratio - 1) / 0.25)
    elseif ratio <= 1.50 then
        return blend(at125, at150, (ratio - 1.25) / 0.25)
    elseif ratio <= 2 then
        return blend(at150, at200, (ratio - 1.50) / 0.50)
    end
    -- Beyond twice shop speed the pass is practically ineffective. Retain a
    -- tiny intermittent contact share instead of creating a hard discontinuity.
    return math.max(at200 * (1 - 0.80
        * math.clamp((ratio - 2) / 0.50, 0, 1)), 0.005)
end
