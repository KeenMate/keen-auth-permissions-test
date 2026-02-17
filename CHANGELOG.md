# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- **Tenants Admin Page** (`TenantsLive`)
  - LiveView page at `/tenants` for managing tenants
  - Search with debounce
  - Create form with title, code, owner ID, removable/assignable options
  - Inline edit for existing tenants
  - Delete with browser confirmation
  - Table showing ID, title, code, UUID, removable/assignable badges
- Added Tenants card to dashboard grid (`bg-success` styling)
- Added Tenants link to dashboard dropdown menu
- Added `/tenants` route in protected scope
- **Users Admin Page** (`UsersLive`)
  - LiveView page at `/users` for managing users
- **Groups Admin Page** (`GroupsLive`)
  - LiveView page at `/groups` for managing groups
- **Permissions Admin Page** (`PermissionsLive`)
  - LiveView page at `/permissions` for viewing permissions
- **Permission Sets Admin Page** (`PermSetsLive`)
  - LiveView page at `/perm-sets` for managing permission sets
  - Inline permissions management modal
- **Events Admin Page** (`EventsLive`)
  - LiveView page at `/events` for viewing user events
- **Demo Page** (`DemoLive`)
  - Permission helpers demonstration page
- **Dashboard** with admin cards and user profile display
- **Authentication**
  - KeenAuth integration with email and Azure AD providers
  - Login, registration, and email confirmation pages
  - Protected routes with session-based authentication
