# JellyFin Server Bootstrap Plan

## 🎯 Objective
Design and implement a reliable bootstrap system for JellyFin server when scaling from 0→1 instances, ensuring configuration and data persistence despite ephemeral container storage.

## 📝 Context & Discussion Summary

### The Problem
- **Current Setup**: JellyFin deployed on Azure Container Apps with scale-to-zero capability
- **Issue**: When container scales from 0→1, JellyFin presents setup wizard (fresh state)
- **Root Cause**: SQLite database was ephemeral, though we now use Azure SQL Database for persistence
- **Impact**: Manual intervention required after every cold start

### Key Discussion Points
1. **Authentication Challenge**: Fresh JellyFin has no admin user to authenticate JellyRoller with
2. **JellyRoller Solution**: Has `server-setup` command that uses public `/Startup/*` endpoints
3. **Backup Strategy**: Need to understand what JellyRoller backups contain vs what persists in SQL
4. **Implementation Approach**: Chose HERO methodology over "YOLO" to minimize risk

### Available Assets
- **JellyRoller CLI**: Docker image `swampyfox/jellyroller-runner` with extensive JellyFin management capabilities
- **Current Infrastructure**: Azure Container Apps + Azure SQL Database + Azure Files
- **Bootstrap Options**: Init containers, sidecar containers, or startup hooks

### Critical Unknowns (Why We Need Testing)
- What exactly gets stored in SQL database vs file system?
- Do JellyRoller backups include complete server state?
- Can setup wizard be bypassed entirely?
- Will init containers work reliably in Container Apps?

### Decision: Systematic Testing Approach
Rather than implementing blindly, we'll use HERO methodology to validate each assumption before building the solution.

## 📋 Current State Analysis

### Infrastructure
- **Platform**: Azure Container Apps with scale-to-zero
- **Database**: Azure SQL Database (persistent)
- **Storage**: Azure Files (persistent) 
- **Problem**: JellyFin configuration is ephemeral, requiring manual setup wizard on each cold start

### Available Tools
- **JellyRoller CLI**: Available as Docker image `swampyfox/jellyroller-runner`
- **JellyRoller Commands**: 
  - `server-setup`: Initial server configuration via startup endpoints
  - `initialize`: Creates API key from admin credentials
  - `create-backup`/`apply-backup`: Backup/restore functionality
  - User management, plugin management, etc.

## 🔬 HERO Test Plan

### Phase 1: Understanding Current Backup/Restore Behavior

#### H1.1: JellyRoller Backup Contents
**Hypothesis**: JellyRoller backups contain complete server state including configuration, users, and database schema.

**Experiment**:
1. Deploy current JellyFin setup
2. Complete manual setup wizard
3. Create test users and configuration
4. Run `jellyroller create-backup`
5. Examine backup contents
6. Scale to zero, then back to one
7. Run `jellyroller apply-backup`

**Success Criteria**:
- [ ] Backup file created successfully
- [ ] Backup contains identifiable configuration data
- [ ] Backup restore recreates users and settings
- [ ] Server functions normally after restore

**Test Script**: `tests/h1-1-backup-contents.ps1`

---

#### H1.2: Database vs File System State
**Hypothesis**: JellyFin stores configuration in both SQL database (persistent) and file system (ephemeral), causing incomplete restoration.

**Experiment**:
1. Fresh JellyFin setup with SQL database
2. Document what gets stored where:
   - SQL database tables and data
   - File system configuration files
3. Scale to zero and examine what persists
4. Scale back to one and document what's missing

**Success Criteria**:
- [ ] Clear mapping of persistent vs ephemeral data
- [ ] Understanding of what causes setup wizard to appear

**Test Script**: `tests/h1-2-state-mapping.ps1`

---

#### H1.3: Setup Wizard Bypass
**Hypothesis**: JellyFin setup wizard can be bypassed by pre-seeding correct configuration files.

**Experiment**:
1. Complete setup wizard manually
2. Copy all configuration files from `/config`
3. Mount these files in a fresh container
4. Verify server starts without setup wizard

**Success Criteria**:
- [ ] Server starts directly to login page
- [ ] Admin user accessible
- [ ] No setup wizard displayed

**Test Script**: `tests/h1-3-config-bypass.ps1`

---

### Phase 2: JellyRoller Integration Testing

#### H2.1: Server-Setup Command
**Hypothesis**: JellyRoller `server-setup` command can fully configure a fresh JellyFin instance without manual intervention.

**Experiment**:
1. Deploy fresh JellyFin instance
2. Create `setup.properties` file with configuration
3. Run `jellyroller server-setup --server-url <url> --filename setup.properties`
4. Verify complete setup without manual steps

**Success Criteria**:
- [ ] Server setup completes without errors
- [ ] Admin user created and accessible
- [ ] Server fully functional

**Test Script**: `tests/h2-1-server-setup.ps1`

---

#### H2.2: Backup-First Bootstrap
**Hypothesis**: We can bootstrap by doing minimal setup then immediately restoring a backup, overriding the fresh configuration.

**Experiment**:
1. Create a "golden master" backup from fully configured server
2. Fresh JellyFin deployment
3. Run minimal `server-setup` (just enough for API access)
4. Run `jellyroller apply-backup` with golden master
5. Verify complete restoration

**Success Criteria**:
- [ ] Golden master backup restores completely
- [ ] All users, settings, and configuration present
- [ ] No conflicts between initial setup and backup

**Test Script**: `tests/h2-2-backup-first.ps1`

---

#### H2.3: Init Container Feasibility
**Hypothesis**: Azure Container Apps init containers can successfully bootstrap JellyFin before the main container starts serving traffic.

**Experiment**:
1. Create init container with JellyRoller
2. Mount shared storage between init and main containers
3. Init container performs bootstrap, signals completion
4. Main container starts with fully configured state

**Success Criteria**:
- [ ] Init container completes successfully
- [ ] Main container starts without setup wizard
- [ ] No race conditions or timing issues
- [ ] Bootstrap failure prevents main container start

**Test Script**: `tests/h2-3-init-container.ps1`

---

### Phase 3: Production Readiness Testing

#### H3.1: Bootstrap Idempotency
**Hypothesis**: Bootstrap process can be run multiple times safely without corruption or duplicate data.

**Experiment**:
1. Run bootstrap process successfully
2. Scale to zero and back to one (triggering re-bootstrap)
3. Manually trigger bootstrap again
4. Verify no data corruption or duplication

**Success Criteria**:
- [ ] Multiple bootstrap runs don't cause errors
- [ ] No duplicate users or configuration
- [ ] System remains stable after repeated bootstraps

**Test Script**: `tests/h3-1-idempotency.ps1`

---

#### H3.2: Partial Failure Recovery
**Hypothesis**: Bootstrap process can recover from partial failures and complete successfully on retry.

**Experiment**:
1. Simulate various failure scenarios:
   - Network timeout during backup restore
   - Corrupted configuration files
   - Database connection issues
2. Verify bootstrap can recover and complete

**Success Criteria**:
- [ ] Bootstrap detects incomplete previous attempts
- [ ] Recovery process completes successfully
- [ ] No manual intervention required

**Test Script**: `tests/h3-2-failure-recovery.ps1`

---

#### H3.3: Performance and Timing
**Hypothesis**: Bootstrap process completes within acceptable time limits for container startup.

**Experiment**:
1. Measure bootstrap time for various scenarios:
   - Fresh setup only
   - Backup restore (various backup sizes)
   - Full bootstrap with users and plugins
2. Verify Azure Container Apps timeout limits

**Success Criteria**:
- [ ] Bootstrap completes within 5 minutes
- [ ] No Container Apps startup timeouts
- [ ] Acceptable cold start times

**Test Script**: `tests/h3-3-performance.ps1`

---

## 🏗️ Implementation Phases

### Phase A: Research & Testing
- Execute all HERO experiments
- Document findings and decision points
- Create proof-of-concept implementations

### Phase B: Core Implementation  
- Implement chosen bootstrap strategy
- Create infrastructure modifications
- Build bootstrap scripts and configurations

### Phase C: Integration & Testing
- End-to-end testing in Azure environment
- Performance optimization
- Documentation and runbooks

### Phase D: Production Deployment
- Blue/green deployment strategy
- Monitoring and alerting
- Rollback procedures

## 📊 Success Metrics

### Functional Requirements
- [ ] JellyFin server starts without manual setup wizard
- [ ] All user accounts and permissions restored
- [ ] Media libraries and metadata intact
- [ ] Plugins and custom configuration preserved

### Non-Functional Requirements  
- [ ] Bootstrap completes in < 5 minutes
- [ ] 99.9% bootstrap success rate
- [ ] No data loss during scaling events
- [ ] Clear failure notifications and recovery procedures

## 🔄 Test Execution Plan

### Week 1: Hypothesis Testing (H1.1 - H1.3)
- Set up test environment
- Execute basic backup/restore experiments
- Document current system behavior

### Week 2: Integration Testing (H2.1 - H2.3)  
- Test JellyRoller automation
- Validate bootstrap approaches
- Prototype init container solution

### Week 3: Production Testing (H3.1 - H3.3)
- Stress test bootstrap process
- Validate reliability and performance
- Create monitoring and alerting

### Week 4: Implementation
- Deploy chosen solution
- Create documentation
- Set up monitoring

## 📁 Test Artifacts

All test scripts will be created in `tests/` directory:
- `tests/h1-1-backup-contents.ps1`
- `tests/h1-2-state-mapping.ps1` 
- `tests/h1-3-config-bypass.ps1`
- `tests/h2-1-server-setup.ps1`
- `tests/h2-2-backup-first.ps1`
- `tests/h2-3-init-container.ps1`
- `tests/h3-1-idempotency.ps1`
- `tests/h3-2-failure-recovery.ps1`
- `tests/h3-3-performance.ps1`

## 📚 Technical References

### JellyRoller Commands (from source analysis)
- `server-setup --server-url <url> --filename <config>`: Initial server configuration using startup endpoints
- `initialize --username <user> --password <pass> --server-url <url>`: Create API key from admin credentials
- `create-backup`: Creates backup with metadata, trickplay, subtitles, database
- `apply-backup --filename <backup>`: Restores from backup file
- `add-users --inputfile <csv>`: Bulk user creation

### JellyFin Startup Endpoints (public, no auth required)
- `POST /Startup/Configuration`: Server settings (country, language, culture)
- `GET /Startup/User`: Required before user creation
- `POST /Startup/User`: Create first admin user
- `POST /Startup/RemoteAccess`: Network settings
- `POST /Startup/Complete`: Finish setup wizard

### Current Infrastructure Files
- `infra/main.bicep`: Main infrastructure template
- `infra/modules/containerapp.bicep`: Container Apps configuration
- `infra/modules/database.bicep`: Azure SQL Database setup
- `azure.yaml`: Azure Developer CLI configuration

## 🎯 Next Steps

### Immediate Actions
1. **Review and approve this plan**
2. **Create test environment** (or use existing deployment)
3. **Begin with H1.1** - Understanding what JellyRoller backups actually contain
4. **Execute tests systematically** - Don't skip ahead until current hypothesis is validated
5. **Document all findings** - Update this plan with results

### For Next Session
When resuming this work:
1. **Point to this document** for full context
2. **Check test results** in the experiments section
3. **Start where we left off** in the systematic testing approach
4. **Update hypothesis status** as we learn more

## 🔄 Status Tracking

### Planning Phase: ✅ COMPLETE
- [x] Problem analysis and scope definition
- [x] HERO test plan creation
- [x] Technical approach options identified
- [x] Risk mitigation strategy established

### Testing Phase: ⏳ PENDING
- [ ] H1.1: Backup contents analysis
- [ ] H1.2: State mapping (SQL vs filesystem)
- [ ] H1.3: Setup wizard bypass testing
- [ ] H2.x: JellyRoller integration tests
- [ ] H3.x: Production readiness validation

### Implementation Phase: ⏳ PENDING
- [ ] Core bootstrap implementation
- [ ] Infrastructure modifications
- [ ] End-to-end testing
- [ ] Production deployment

---

*This plan follows the HERO methodology to ensure we build a robust, well-tested bootstrap solution rather than hoping for the best. All context and decisions are documented here for future reference.*
