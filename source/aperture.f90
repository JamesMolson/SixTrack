module aperture
  ! Aperture check module
  ! A.Mereghetti, P.Garcia Ortega and D.Sinuela Pastor, for the FLUKA Team
  ! J.Molson, BE/ABP-HSS
  ! K.Sjobak, BE/ABP-LAT

  use floatPrecision
  use mathlib_bouncer
  use numerical_constants

  use parpro !For nele, npart

  !contains pstop(npart) etc
  use mod_commonmn
  use crcoall
  use mod_common
  use mod_commons
  use mod_commont
  use mod_commond

  use mod_hions
  use mod_alloc
#ifdef HDF5
  use hdf5_output
#endif

  implicit none

  ! A.Mereghetti, P.Garcia Ortega and D.Sinuela Pastor, for the FLUKA Team
  ! last modified: 02-03-2018
  ! always in main code

  logical, save :: limifound                       ! limi block in fort.3

  integer, allocatable, save :: kape(:)            ! type of aperture (nele)
  ! aperture parameteres ape(9,nele)
  ! ape(1,:): hor dimension (RECT/RECTELLIPSE/OCT) [mm]
  ! ape(2,:): ver dimension (RECT/RECTELLIPSE/OCT) [mm]
  ! ape(3,:): hor dimension (CIRC/ELLI/RECTELLIPSE/RACETR) [mm]
  ! ape(4,:): ver dimension (CIRC/ELLI/RECTELLIPSE/RACETR) [mm]
  ! ape(5,:): m of sloped side (OCT) []
  ! ape(6,:): q of sloped side (OCT) [mm]
  ! ape(7,:): tilt angle of marker (all) [rad]
  ! ape(8,:): hor offset of marker (all) [mm]
  ! ape(9,:): ver offset of marker (all) [mm]
  real(kind=fPrec), allocatable, save ::  ape(:,:) !(9,nele)
  logical, allocatable, save :: lapeofftlt(:)      ! aperture is tilted/offcentred (nele)

  ! save (i.e. do not kill) lost particles
  logical, save :: apflag                          ! save or not
  integer, save :: plost(npart)                    ! particle ID

  integer, save :: aperture_napxStart              ! initial napx

  ! dump aperture profile:
  logical, save :: ldmpaper                        ! dump or not
  integer, save :: aperunit                        ! fortran unit
  character(len=16), save :: aper_filename         ! file name
  logical, save :: ldmpaperMem                     ! dump aperture marker parameters as in memory
  ! load aperture markers from external file:
  integer, save :: loadunit                        ! fortran unit
  character(len=16), save :: load_file             ! file name

  ! A.Mereghetti and P.Garcia Ortega, for the FLUKA Team
  ! last modified: 02-03-2018
  ! variables for back-tracking
  logical, save :: lbacktracking                   ! activate back-tracking
  real(kind=fPrec), save :: xLast(2,npart)         ! position after last thick element [mm]
  real(kind=fPrec), save :: yLast(2,npart)         ! angles after last thick element [mrad]
  real(kind=fPrec), save :: ejfvLast(npart)        ! linear momentum [MeV/c]
  real(kind=fPrec), save :: ejvLast(npart)         ! total energy [MeV]
  real(kind=fPrec), save :: nucmLast(npart)        ! nuclear mass [GeV/c2]
  real(kind=fPrec), save :: sigmvLast(npart)       ! lag [mm]
  real(kind=fPrec), save :: dpsvLast(npart)        !
  integer, save :: naaLast(npart), nzzLast(npart)  ! nuclear mass and atomic number []
  real(kind=fPrec), save :: bktpre                 ! precision of back-tracking [m]
  integer, save :: iLast, ixLast                   ! indeces of last aperture marker
  integer, save :: iLastThick, ixLastThick         ! indeces of last thick element
  integer, save :: iBckTypeLast                    ! map of back-tracking - it follows kz values, eg:
                                                   ! 0 : drift (the only one available)

  ! A.Mereghetti (CERN, BE/ABP-HSS), 2018-03-22
  ! x-sec at specific locations
  integer, save :: mxsec                           ! current number of requested x-secs
  integer, parameter :: nxsec=10                   ! max number of requested x-secs
  integer, save :: xsecunit(nxsec)                 ! fortran units
  character(len=16), save :: xsec_filename(nxsec)  ! file names
  real(kind=fPrec), save :: sLocMin(nxsec), sLocMax(nxsec), sLocDel(nxsec) ! locations
  integer, save :: nAzimuts(nxsec)                 ! number of points (azimuth angles)
  integer, parameter :: nAzimutDef=72              ! default number of points


  ! aperture types  -- kape
  ! no aperture     -- 0
  ! circle          -- 1
  ! rectangle       -- 2
  ! ellipse         -- 3
  ! rectellipse     -- 4
  ! octagon         -- 5
  ! racetrack       -- 6
  ! transition      -- 7
  character(len=2), parameter, dimension(-1:6) :: apeName=(/'TR','NA','CR','RE','EL','RL','OC','RT'/)

  ! precision parameters:
  real(kind=fPrec), parameter :: aPrec=c1m6 ! identify two ap. markers as identical [mm]
  real(kind=fPrec), parameter :: sPrec=c1m7 ! identify two ap. markers as at the same s-pos [m]

#ifdef HDF5
  integer, private, save :: aper_fmtLostPart
  integer, private, save :: aper_setLostPart
#endif

contains


subroutine aperture_allocate_arrays
  implicit none
  integer stat

  call alloc(kape,nele,0,'kape')
  call alloc(lapeofftlt,nele,.FALSE.,'lapeofftlt')
  call alloc(ape,9,nele,zero,'ape')
end subroutine aperture_allocate_arrays


subroutine aperture_expand_arrays(nele_new)
  implicit none
  integer, intent(in) :: nele_new

  call resize(kape,nele_new,0,'kape')
  call resize(lapeofftlt,nele_new,.FALSE.,'lapeofftlt')
  call resize(ape,9,nele_new,zero,'ape')

end subroutine aperture_expand_arrays


subroutine aperture_comnul

  use numerical_constants
  implicit none
  integer ii, jj

  limifound=.false.

  apflag=.false.
  do ii=1,npart
     plost(ii)=0
  end do

  ldmpaper      = .false.
  aperunit      = 0
  aper_filename = char(0)
  ldmpaperMem   = .false.
  loadunit      = 3 ! default: read aperture markers in fort.3
  load_file     = char(0)

  lbacktracking = .false. ! backtracking off by default
  do ii=1,npart
     do jj=1,2
        xLast(jj,ii)=zero
        yLast(jj,ii)=zero
     end do
     ejfvLast(jj)=zero
     ejvLast(jj)=zero
     nucmLast(jj)=zero
     sigmvLast(jj)=zero
     dpsvLast(jj)=zero
     naaLast(jj)=0
     nzzLast(jj)=0
  end do
  bktpre=c1m1 ! default precision: 0.1m
  iLast = 0
  ixLast = 0
  iLastThick = 0
  ixLastThick = 0
  iBckTypeLast = 0

  mxsec = 0
  do ii=1,nxsec
     xsecunit(ii)=0
     xsec_filename(ii)=char(0)
     sLocMin(ii)=zero
     sLocMax(ii)=zero
     sLocDel(ii)=zero
     nAzimuts(ii)=nAzimutDef
  enddo

  aperture_napxStart=0

  return

end subroutine aperture_comnul

! ================================================================================================ !
!  Aperture module initialisation
!  V.K. Berglyd Olsen, BR-ABP-HSS
!  Last modified: 2018-05-15
! ================================================================================================ !
subroutine aperture_init

  implicit none

#ifdef HDF5
  type(h5_dataField), allocatable :: setFields(:)
#endif
  logical isOpen

#ifdef HDF5
  if(h5_useForAPER) then
    call h5_initForAperture
#ifdef FLUKA
    allocate(setFields(17))
#else
    allocate(setFields(15))
#endif
    setFields(1)  = h5_dataField(name="TURN",         type=h5_typeInt)
    setFields(2)  = h5_dataField(name="BLOCK",        type=h5_typeInt)
    setFields(3)  = h5_dataField(name="BEZID",        type=h5_typeInt)
    setFields(4)  = h5_dataField(name="BEZ",          type=h5_typeChar, size=max_name_len)
    setFields(5)  = h5_dataField(name="SLOS",         type=h5_typeReal)
    setFields(6)  = h5_dataField(name="X",            type=h5_typeReal)
    setFields(7)  = h5_dataField(name="XP",           type=h5_typeReal)
    setFields(8)  = h5_dataField(name="Y",            type=h5_typeReal)
    setFields(9)  = h5_dataField(name="YP",           type=h5_typeReal)
    setFields(10) = h5_dataField(name="ETOT",         type=h5_typeReal)
    setFields(11) = h5_dataField(name="DE",           type=h5_typeReal)
    setFields(12) = h5_dataField(name="DT",           type=h5_typeReal)
    setFields(13) = h5_dataField(name="ATOMA",        type=h5_typeInt)
    setFields(14) = h5_dataField(name="ATOMZ",        type=h5_typeInt)
#ifdef FLUKA
    setFields(15) = h5_dataField(name="FLUKA_UID",    type=h5_typeInt)
    setFields(16) = h5_dataField(name="FLUKA_GEN",    type=h5_typeInt)
    setFields(17) = h5_dataField(name="FLUKA_WEIGHT", type=h5_typeReal)
#else
    setFields(15) = h5_dataField(name="PARTID",       type=h5_typeInt)
#endif
    call h5_createFormat("aperLostPart", setFields, aper_fmtLostPart)
    call h5_createDataSet("lostpart", h5_aperID, aper_fmtLostPart, aper_setLostPart)
  else
#endif
    inquire(unit=999, opened=isOpen)
    if(isOpen) then
      write(lout,"(a)") "APER> ERROR Unit 999 is already open."
      call prror(-1)
    end if
    open(unit=999)
    write(999,"(a)") "# turn block bezid bez slos "// &
#ifdef FLUKA
      "fluka_uid fluka_gen fluka_weight "// &
#else
      "partid "// &
#endif
      "x y xp yp etot dE dT A_atom Z_atom "
#ifdef HDF5
  end if
#endif

end subroutine aperture_init

subroutine aperture_nul( ix )
  !-----------------------------------------------------------------------
  ! A.Mereghetti (CERN, BE-ABP-HSS), 2018-03-21
  ! initialise aperture marker to null
  !-----------------------------------------------------------------------
  implicit none
  integer ix, jj
  kape(ix)=0
  do jj=1,9
     ape(jj,ix)=zero
  end do
  lapeofftlt(ix)=.false.
end subroutine aperture_nul


subroutine aperture_initCR( ix, aper )
  !-----------------------------------------------------------------------
  ! A.Mereghetti (CERN, BE-ABP-HSS), 2018-03-21
  ! initialise aperture marker to circle
  !-----------------------------------------------------------------------
  implicit none
  integer ix
  real(kind=fPrec) aper
  call aperture_nul( ix )
  kape(ix)=1
  ape(1,ix)=aper
  ape(2,ix)=aper
  ape(3,ix)=aper
  ape(4,ix)=aper
  ape(5,ix)=-one
  ape(6,ix)=ape(1,ix)*sqrt(two)
end subroutine aperture_initCR


subroutine aperture_initRE( ix, aprx, apry )
  !-----------------------------------------------------------------------
  ! A.Mereghetti (CERN, BE-ABP-HSS), 2018-03-21
  ! initialise aperture marker to rectangle
  !-----------------------------------------------------------------------
  implicit none
  integer ix
  real(kind=fPrec) aprx, apry
  call aperture_nul( ix )
  kape(ix)=2
  ape(1,ix)=aprx
  ape(2,ix)=apry
  ape(3,ix)=aprx*sqrt(two)
  ape(4,ix)=apry*sqrt(two)
  ape(5,ix)=-one
  ape(6,ix)=ape(2,ix)-ape(5,ix)*ape(1,ix)
end subroutine aperture_initRE


subroutine aperture_initEL( ix, apex, apey )
  !-----------------------------------------------------------------------
  ! A.Mereghetti (CERN, BE-ABP-HSS), 2018-03-21
  ! initialise aperture marker to ellipse
  !-----------------------------------------------------------------------
  implicit none
  integer ix
  real(kind=fPrec) apex, apey
  call aperture_nul( ix )
  kape(ix)=3
  ape(1,ix)=apex
  ape(2,ix)=apey
  ape(3,ix)=apex
  ape(4,ix)=apey
  ape(5,ix)=-one
  ape(6,ix)=sqrt(ape(3,ix)**2+ape(4,ix)**2)
end subroutine aperture_initEL


subroutine aperture_initRL( ix, aprx, apry, apex, apey )
  !-----------------------------------------------------------------------
  ! A.Mereghetti (CERN, BE-ABP-HSS), 2018-03-21
  ! initialise aperture marker to rectellipse
  !-----------------------------------------------------------------------
  implicit none
  integer ix
  real(kind=fPrec) aprx, apry, apex, apey
  call aperture_nul( ix )
  kape(ix)=4
  ape(1,ix)=aprx
  ape(2,ix)=apry
  ape(3,ix)=apex
  ape(4,ix)=apey
  ape(5,ix)=-one
  ape(6,ix)=max(ape(2,ix)-ape(5,ix)*ape(1,ix),sqrt(ape(3,ix)**2+ape(4,ix)**2))
end subroutine aperture_initRL


subroutine aperture_initOC( ix, aprx, apry, theta1, theta2 )
  !-----------------------------------------------------------------------
  ! A.Mereghetti (CERN, BE-ABP-HSS), 2018-03-21
  ! initialise aperture marker to octagon
  !-----------------------------------------------------------------------
  implicit none
  integer ix
  real(kind=fPrec) aprx, apry, theta1, theta2, N
  call aperture_nul( ix )
  kape(ix)=5
  ape(1,ix)=aprx
  ape(2,ix)=apry
  ! x1=aprx=ape(1,ix)
  ! y1=ape(1,ix)*tan(theta1)
  ! x2=ape(2,ix)/tan(theta2)
  ! y2=apry=ape(2,ix)
  ! ellipse circumscribed to octagon
  ! N=x1^2*y2^2-y1^2*x2^2
  ! a=sqrt(N/(y2^2-y1^2))
  ! b=sqrt(N/(x1^2-x2^2))
  N=((ape(1,ix)*ape(2,ix))*(one+tan_mb(theta1)/tan_mb(theta2)))* &
 &  ((ape(1,ix)*ape(2,ix))*(one-tan_mb(theta1)/tan_mb(theta2)))
  ape(3,ix)=sqrt(N/((ape(2,ix)+ape(1,ix)*tan_mb(theta2))*(ape(2,ix)-ape(1,ix)*tan_mb(theta2))))
  ape(4,ix)=sqrt(N/((ape(1,ix)+ape(2,ix)/tan_mb(theta2))*(ape(1,ix)-ape(2,ix)/tan_mb(theta2))))
  ! m and q of sloped side
  ! m = (y2-y1)/(x2-x1)
  ! q = y1 -m*x1
  ape(5,ix)=(ape(2,ix)-ape(1,ix)*tan_mb(theta1))/(ape(2,ix)/tan_mb(theta2)-ape(1,ix))
  ape(6,ix)=ape(1,ix)*tan_mb(theta1)-ape(5,ix)*ape(1,ix)
end subroutine aperture_initOC


subroutine aperture_initRT( ix, aprx, apry, radius )
  !-----------------------------------------------------------------------
  ! A.Mereghetti (CERN, BE-ABP-HSS), 2018-03-22
  ! initialise aperture marker to racetrack
  !-----------------------------------------------------------------------
  implicit none
  integer ix
  real(kind=fPrec) aprx, apry, radius
  call aperture_nul( ix )
  kape(ix)=6
  ape(1,ix)=aprx
  ape(2,ix)=apry
  ape(3,ix)=radius
  ape(4,ix)=radius
  ape(5,ix)=-one
  ape(6,ix)=sqrt(ape(3,ix)**2+ape(4,ix)**2)+(ape(1,ix)-ape(3,ix))+(ape(2,ix)-ape(4,ix))
end subroutine aperture_initRT


subroutine aperture_initTR( ix, aprx, apry, apex, apey, theta1, theta2 )
  !-----------------------------------------------------------------------
  ! A.Mereghetti (CERN, BE-ABP-HSS), 2018-03-21
  ! initialise aperture marker to transition
  !-----------------------------------------------------------------------
  implicit none
  integer ix
  real(kind=fPrec) aprx, apry, apex, apey, theta1, theta2
  call aperture_nul( ix )
  kape(ix)=5
  ape(1,ix)=aprx
  ape(2,ix)=apry
  ape(3,ix)=apex
  ape(4,ix)=apey
  ! x1=aprx=ape(1,ix)
  ! y1=ape(1,ix)*tan_mb(theta1)
  ! x2=ape(2,ix)/tan_mb(theta2)
  ! y2=apry=ape(2,ix)
  ! m and q of sloped side
  ! m = (y2-y1)/(x2-x1)
  ! q = y1 -m*x1
  ape(5,ix)=(ape(2,ix)-ape(1,ix)*tan_mb(theta1))/(ape(2,ix)/tan_mb(theta2)-ape(1,ix))
  ape(6,ix)=ape(1,ix)*tan_mb(theta1)-ape(5,ix)*ape(1,ix)
end subroutine aperture_initTR


subroutine aperture_initroffpos( ix, tilt, xoff, yoff )
  !-----------------------------------------------------------------------
  ! A.Mereghetti (CERN, BE-ABP-HSS), 2018-03-22
  ! initialise offset/tilt of aperture marker
  !-----------------------------------------------------------------------
  implicit none
  integer ix
  real(kind=fPrec) tilt, xoff, yoff
  ape(7,ix)=tilt
  ape(8,ix)=xoff
  ape(9,ix)=yoff
  lapeofftlt(ix)=ape(7,ix).ne.zero.or.ape(8,ix).ne.zero.or.ape(9,ix).ne.zero
end subroutine aperture_initroffpos


subroutine aperture_saveLastMarker( i, ix )
  !-----------------------------------------------------------------------
  ! A.Mereghetti (CERN, BE-ABP-HSS), 2018-03-07
  ! save last aperture marker
  !-----------------------------------------------------------------------

  implicit none
  ! interface variables
  integer i, ix
  iLast = i
  ixLast = ix
  return

end subroutine aperture_saveLastMarker


subroutine aperture_saveLastCoordinates( i, ix, iBack )
  !-----------------------------------------------------------------------
  ! A.Mereghetti (CERN, BE-ABP-HSS), 2018-03-21
  ! save particle coordinates at last aperture check
  !-----------------------------------------------------------------------

  use mod_commonmn ! for napx, xv and yv
  implicit none
  ! interface variables
  integer i, ix, iBack
  ! temporary variables
  integer j

  do j=1,napx
     xLast(1,j) = xv(1,j)
     xLast(2,j) = xv(2,j)
     yLast(1,j) = yv(1,j)
     yLast(2,j) = yv(2,j)
     ejfvLast(j) = ejfv(j)
     ejvLast(j) = ejv(j)
     nucmLast(j) = nucm(j)
     sigmvLast(j) = sigmv(j)
     dpsvLast(j) = dpsv(j)
     naaLast(j) = naa(j)
     nzzLast(j) = nzz(j)
  end do
  iLastThick = i
  ixLastThick = ix
  iBckTypeLast = iBack
  return

end subroutine aperture_saveLastCoordinates


subroutine aperture_backTrackingInit
  !-----------------------------------------------------------------------
  ! A.Mereghetti (CERN, BE-ABP-HSS), 2018-03-07
  ! initialise variables for back-tracking
  !-----------------------------------------------------------------------
  use parpro     ! for nblo
  use mod_common ! for ic(i)
  use crcoall    ! for lout
  implicit none
  ! temporary variables
  integer i, ix

  i=1
  ix=ic(i)-nblo
  if ( ix.lt.0 ) then
     write(lout,*)'Impossible to properly initialise backtracking: first '// &
 &   'element of lattice structure is not a single element'
     call prror(-1)
  endif
  if ( kape(ix).eq.0 ) then
     write(lout,*)'Impossible to properly initialise backtracking: first '// &
 &   'element of lattice structure is not assigned an aperture profile'
     call prror(-1)
  endif

  call aperture_saveLastCoordinates( i, ix, -1 )
  call aperture_saveLastMarker( i, ix )

  return

end subroutine aperture_backTrackingInit


subroutine lostpart(turn, i, ix, llost, nthinerr)
!-----------------------------------------------------------------------
!     P.Garcia Ortega, A.Mereghetti and D.Sinuela Pastor, for the FLUKA Team
!     last modified:  8-12-2014
!     aperture check and dump lost particles
!     always in main code
!-----------------------------------------------------------------------
!     7 April 2014
!-----------------------------------------------------------------------

  use physical_constants

#ifdef FLUKA
  use mod_fluka
#endif

#ifdef ROOT
  use iso_c_binding
  use root_output
#endif

#ifdef COLLIMAT
  use collimation
#endif

  implicit none

! parameters
  integer turn  ! turn number
  integer i     ! element entry in the lattice
  integer ix    ! single element type index
  logical llost ! at least one particle was lost


! logical isnan
  logical myisnan
  integer ib2,ib3,ilostch,j,jj,jj1,jjx

! temporary variables
  logical lparID, llostp(npart)
  integer nthinerr
  real(kind=fPrec) apxx, apyy, apxy, aps, apc, radius2
  real(kind=fPrec) xchk(2)

#ifdef ROOT
  character(len=max_name_len+1) this_name
#endif

! A.Mereghetti and P.Garcia Ortega, for the FLUKA Team
! last modified: 12-06-2014
! additional variables for back-tracking, when computing locations of
! lost particles
! inserted in main code by the 'backtrk' compilation flag
  integer niter       ! number of iterations
  integer kapert      ! temporal integer for aperture type
  logical llos        ! temporal logic array for interpolation
  logical lback       ! actually perform backtracking
  real(kind=fPrec) xlos(2), ylos(2), aprr(9), step, length, slos, ejfvlos, ejvlos, nucmlos, sigmvlos, dpsvlos
  integer naalos, nzzlos

  save

  !-----------------------------------------------------------------------
  ! check against current aperture marker
  !-----------------------------------------------------------------------

  llost=.false.
  lback=.false.

  if (.not.limifound.or.kape(ix).eq.0) then
    ! limi block not there or aperture type not assigned
    ! general check (set in the ITER block)
    do j=1,napx
      llostp(j)=(abs(xv(1,j)).gt.aper(1)).or.(abs(xv(2,j)).gt.aper(2)).or. &
 &                       (xv(1,j).ne.xv(1,j)).or.(xv(2,j).ne.xv(2,j))
      llost=llost.or.llostp(j)
    end do

  else

    ! go through all possible types
    select case(kape(ix))

    case (-1) ! Transition
      apxx = ape(3,ix)**2.
      apyy = ape(4,ix)**2.
      apxy = apxx * apyy
      do j=1,napx
        if (lapeofftlt(ix)) then
          if (lbacktracking) then
            call roffpos(xLast(1,j),xLast(2,j),xchk(1),xchk(2),ape(7,ix),ape(8,ix),ape(9,ix))
          else
            call roffpos(xv(1,j),xv(2,j),xchk(1),xchk(2),ape(7,ix),ape(8,ix),ape(9,ix))
          end if
          llostp(j)=checkTR(xchk(1),xchk(2),ape(1,ix),ape(2,ix),ape(3,ix),ape(4,ix),apxx,apyy,apxy,ape(5,ix),ape(6,ix)).or. &
 &                 myisnan(xchk(1),xchk(1)).or.myisnan(xchk(2),xchk(2))
        else
          if (lbacktracking) then
            llostp(j)= &
 &                  checkTR(xLast(1,j),xLast(2,j),ape(1,ix),ape(2,ix),ape(3,ix),ape(4,ix),apxx,apyy,apxy,ape(5,ix),ape(6,ix)) .or. &
 &                  myisnan(xLast(1,j),xLast(1,j)).or.myisnan(xLast(2,j),xLast(2,j))
          else
            llostp(j)= &
 &                  checkTR(xv(1,j),xv(2,j),ape(1,ix),ape(2,ix),ape(3,ix),ape(4,ix),apxx,apyy,apxy,ape(5,ix),ape(6,ix))       .or. &
 &                  myisnan(xv(1,j),xv(1,j)).or.myisnan(xv(2,j),xv(2,j))
          end if
        end if
        llost=llost.or.llostp(j)
      end do

    case (1) ! circle
      radius2 = ape(3,ix)**2
      do j=1,napx
        if (lapeofftlt(ix)) then
          if (lbacktracking) then
            call roffpos(xLast(1,j),xLast(2,j),xchk(1),xchk(2),ape(7,ix),ape(8,ix),ape(9,ix))
          else
            call roffpos(xv(1,j),xv(2,j),xchk(1),xchk(2),ape(7,ix),ape(8,ix),ape(9,ix))
          end if
          llostp(j)=checkCR( xchk(1),xchk(2),radius2 ) .or. &
 &                 myisnan(xchk(1),xchk(1)).or.myisnan(xchk(2),xchk(2))
        else
          if (lbacktracking) then
            llostp(j)=checkCR( xLast(1,j),xLast(2,j),radius2 ) .or. &
 &                 myisnan(xLast(1,j),xLast(1,j)).or.myisnan(xLast(2,j),xLast(2,j))
          else
            llostp(j)=checkCR( xv(1,j),xv(2,j),radius2 ) .or. &
 &                 myisnan(xv(1,j),xv(1,j)).or.myisnan(xv(2,j),xv(2,j))
          end if
        end if
        llost=llost.or.llostp(j)
      end do

    case (2) ! Rectangle
      do j=1,napx
        if (lapeofftlt(ix)) then
          if (lbacktracking) then
            call roffpos(xLast(1,j),xLast(2,j),xchk(1),xchk(2),ape(7,ix),ape(8,ix),ape(9,ix))
          else
            call roffpos(xv(1,j),xv(2,j),xchk(1),xchk(2),ape(7,ix),ape(8,ix),ape(9,ix))
          end if
          llostp(j)=checkRE( xchk(1),xchk(2),ape(1,ix),ape(2,ix) ) .or. &
 &                 myisnan(xchk(1),xchk(1)).or.myisnan(xchk(2),xchk(2))
        else
          if (lbacktracking) then
            llostp(j)=checkRE( xLast(1,j),xLast(2,j),ape(1,ix),ape(2,ix) ) .or. &
 &                 myisnan(xLast(1,j),xLast(1,j)).or.myisnan(xLast(2,j),xLast(2,j))
          else
            llostp(j)=checkRE( xv(1,j),xv(2,j),ape(1,ix),ape(2,ix) ) .or. &
 &                 myisnan(xv(1,j),xv(1,j)).or.myisnan(xv(2,j),xv(2,j))
          end if
        end if
        llost=llost.or.llostp(j)
      end do

    case (3) ! Ellipse
      apxx = ape(3,ix)**2.
      apyy = ape(4,ix)**2.
      apxy = apxx * apyy
      do j=1,napx
        if (lapeofftlt(ix)) then
          if (lbacktracking) then
            call roffpos(xLast(1,j),xLast(2,j),xchk(1),xchk(2),ape(7,ix),ape(8,ix),ape(9,ix))
          else
            call roffpos(xv(1,j),xv(2,j),xchk(1),xchk(2),ape(7,ix),ape(8,ix),ape(9,ix))
          end if
          llostp(j)=checkEL( xchk(1),xchk(2),apxx,apyy,apxy ) .or. &
 &                 myisnan(xchk(1),xchk(1)).or.myisnan(xchk(2),xchk(2))
        else
          if (lbacktracking) then
            llostp(j)=checkEL( xLast(1,j),xLast(2,j),apxx,apyy,apxy ) .or. &
 &                 myisnan(xLast(1,j),xLast(1,j)).or.myisnan(xLast(2,j),xLast(2,j))
          else
            llostp(j)=checkEL( xv(1,j),xv(2,j),apxx,apyy,apxy ) .or. &
 &                 myisnan(xv(1,j),xv(1,j)).or.myisnan(xv(2,j),xv(2,j))
          end if
        end if
        llost=llost.or.llostp(j)
      end do

    case (4) ! RectEllipse
      apxx = ape(3,ix)**2.
      apyy = ape(4,ix)**2.
      apxy = apxx * apyy
      do j=1,napx
        if (lapeofftlt(ix)) then
          if (lbacktracking) then
            call roffpos(xLast(1,j),xLast(2,j),xchk(1),xchk(2),ape(7,ix),ape(8,ix),ape(9,ix))
          else
            call roffpos(xv(1,j),xv(2,j),xchk(1),xchk(2),ape(7,ix),ape(8,ix),ape(9,ix))
          end if
          llostp(j)=checkRL( xchk(1),xchk(2),ape(1,ix),ape(2,ix),apxx,apyy,apxy ) .or. &
 &                 myisnan(xchk(1),xchk(1)).or.myisnan(xchk(2),xchk(2))
        else
          if (lbacktracking) then
            llostp(j)=checkRL( xLast(1,j),xLast(2,j),ape(1,ix),ape(2,ix),apxx,apyy,apxy ) .or. &
 &                 myisnan(xLast(1,j),xLast(1,j)).or.myisnan(xLast(2,j),xLast(2,j))
          else
            llostp(j)=checkRL( xv(1,j),xv(2,j),ape(1,ix),ape(2,ix),apxx,apyy,apxy ) .or. &
 &                 myisnan(xv(1,j),xv(1,j)).or.myisnan(xv(2,j),xv(2,j))
          end if
        end if
        llost=llost.or.llostp(j)
      end do

    case (5) ! Octagon
      do j=1,napx
        if (lapeofftlt(ix)) then
          if (lbacktracking) then
            call roffpos(xLast(1,j),xLast(2,j),xchk(1),xchk(2),ape(7,ix),ape(8,ix),ape(9,ix))
          else
            call roffpos(xv(1,j),xv(2,j),xchk(1),xchk(2),ape(7,ix),ape(8,ix),ape(9,ix))
          end if
          llostp(j)=checkOC(xchk(1),xchk(2),ape(1,ix),ape(2,ix),ape(5,ix),ape(6,ix)).or. &
 &                 myisnan(xchk(1),xchk(1)).or.myisnan(xchk(2),xchk(2))
        else
          if (lbacktracking) then
            llostp(j)=checkOC(xLast(1,j),xLast(2,j),ape(1,ix),ape(2,ix),ape(5,ix),ape(6,ix)).or. &
 &                 myisnan(xLast(1,j),xLast(1,j)).or.myisnan(xLast(2,j),xLast(2,j))
          else
            llostp(j)=checkOC(xv(1,j),xv(2,j),ape(1,ix),ape(2,ix),ape(5,ix),ape(6,ix)).or. &
 &                 myisnan(xv(1,j),xv(1,j)).or.myisnan(xv(2,j),xv(2,j))
          end if
        end if
        llost=llost.or.llostp(j)
      end do

    case (6) ! Racetrack
      !   NB: it follows the MadX definition
      apxy = ape(3,ix)**2.
      do j=1,napx
        if (lapeofftlt(ix)) then
          if (lbacktracking) then
            call roffpos(xLast(1,j),xLast(2,j),xchk(1),xchk(2),ape(7,ix),ape(8,ix),ape(9,ix))
          else
            call roffpos(xv(1,j),xv(2,j),xchk(1),xchk(2),ape(7,ix),ape(8,ix),ape(9,ix))
          end if
          llostp(j)=checkRT(xchk(1),xchk(2),ape(1,ix),ape(2,ix),ape(3,ix),apxy).or. &
 &                 myisnan(xchk(1),xchk(1)).or.myisnan(xchk(2),xchk(2))
        else
          if (lbacktracking) then
            llostp(j)=checkRT(xLast(1,j),xLast(2,j),ape(1,ix),ape(2,ix),ape(3,ix),apxy).or. &
 &                 myisnan(xLast(1,j),xLast(1,j)).or.myisnan(xLast(2,j),xLast(2,j))
          else
            llostp(j)=checkRT(xv(1,j),xv(2,j),ape(1,ix),ape(2,ix),ape(3,ix),apxy).or. &
 &                 myisnan(xv(1,j),xv(1,j)).or.myisnan(xv(2,j),xv(2,j))
          end if
        end if
        llost=llost.or.llostp(j)
      end do

    end select
  end if ! if(.not.limifound.or.kape(ix).eq.0)

  !-----------------------------------------------------------------------
  ! dump coordinates in case of losses
  ! if back-tracking is requested, get more detailed point of loss
  ! for the moment, only bi-section method
  !-----------------------------------------------------------------------

  if (llost) then

    if (lbacktracking.and.kape(ix).ne.0.and.iBckTypeLast.ne.0) then
      lback=.true.
      ! Length between elements
      length = dcum(i)-dcum(iLast)
      ! - pay attention to overflow:
      if( length .lt. zero ) length = length+tlen
      ! - pay attention to too short thick elements
      if( length .le. bktpre ) lback=.false.
    end if
    ! Number of iterations for bisection method (ln(2x/precision)/ln(2)+1)
    if (lback) niter=nint(1.442695040889_fPrec*log_mb(two*length/bktpre)+2)

    do j=1,napx
      if(llostp(j)) then
        ! treat a lost particle

        ! ==============================================================
        ! point of loss
        if (lback) then
          ! A. Mereghetti and P. Garcia Ortega, for the FLUKA Team
          ! last modified: 21-03-2018
          ! back-track particles, in order to better estimate actual loss point

          ylos(1)=yLast(1,j)
          ylos(2)=yLast(2,j)

          ! actual algorithm
          llos    = llostp(j)
          step    = one
          do jj=1,niter
            ! current step (bisection method):
            if( llos ) then
              step = step - one / (two**(jj))
            else
              step = step + one / (two**(jj))
            end if
            ! - step discretized if last iteration, to compare with BeamLossPattern
            if(jj.eq.niter) then
              slos = int((dcum(iLast)+length*step)/bktpre+one)*bktpre
              step = (slos-dcum(iLast))/length
            end if
            ! - particle coordinates at current step
            select case(iBckTypeLast)
            case (0)
               ! back-track along a drift
               xlos(1) = xLast(1,j) -yLast(1,j)*(one-step)*length
               xlos(2) = xLast(2,j) -yLast(2,j)*(one-step)*length
               slos    = dcum(iLast)-(one-step)*length
            end select
            ! - aperture at current step
            call interp_aperture( iLast,ixLast, i,ix, kapert,aprr, slos )

            ! Check aperture
            if( lapeofftlt(ix).or.lapeofftlt(ixLast) ) then
              call roffpos( xlos(1), xlos(2), xchk(1),xchk(2), aprr(7), aprr(8), aprr(9) )
            else
              xchk(1) = xlos(1)
              xchk(2) = xlos(2)
            end if
            select case(kapert)
            case(-1) ! Transition
              apxx = aprr(3)**2.
              apyy = aprr(4)**2.
              apxy = apxx * apyy
              llos=checkTR(xchk(1),xchk(2),aprr(1),aprr(2),aprr(3),aprr(4),apxx,apyy,apxy,aprr(5),aprr(6)).or. &
 &                 myisnan(xchk(1),xchk(1)).or.myisnan(xchk(2),xchk(2))
            case (1) ! Circle
              radius2 = aprr(3)**2
              llos=checkCR(xchk(1),xchk(2),radius2) .or. &
 &                  myisnan(xchk(1),xchk(1)).or.myisnan(xchk(2),xchk(2))
            case (2) ! Rectangle
              llos=checkRE(xchk(1),xchk(2),aprr(1),aprr(2)) .or. &
 &                  myisnan(xchk(1),xchk(1)).or.myisnan(xchk(2),xchk(2))
            case (3) ! Ellipse
              apxx = aprr(3)**2.
              apyy = aprr(4)**2.
              apxy = apxx * apyy
              llos=checkEL( xchk(1),xchk(2),apxx,apyy,apxy )  .or. &
 &                  myisnan(xchk(1),xchk(1)).or.myisnan(xchk(2),xchk(2))
            case (4) ! RectEllipse
              apxx = aprr(3)**2.
              apyy = aprr(4)**2.
              apxy = apxx * apyy
              llos = checkRL( xchk(1),xchk(2),aprr(1),aprr(2),apxx, apyy, apxy ) .or. &
 &                      myisnan(xchk(1),xchk(1)).or.myisnan(xchk(2),xchk(2))
            case (5) ! Octagon
              llos=checkOC(xchk(1), xchk(2), aprr(1), aprr(2), aprr(5), aprr(6) ) .or. &
 &                    myisnan(xchk(1),xchk(1)).or.myisnan(xchk(2),xchk(2))
            case (6) ! RaceTrack
              llos=checkRT( xchk(1), xchk(2), aprr(1), aprr(2), aprr(3), aprr(3)**2. ) .or. &
 &                    myisnan(xchk(1),xchk(1)).or.myisnan(xchk(2),xchk(2))
            end select
          end do !do jj=1,niter
          ! pay attention to overflow
          if ( slos.gt.tlen ) slos=slos-tlen
       else
          if (lbacktracking) then
             xlos(1) = xLast(1,j)
             xlos(2) = xLast(2,j)
             ylos(1) = yLast(1,j)
             ylos(2) = yLast(2,j)
             slos    = dcum(iLast)
          else
             xlos(1) = xv(1,j)
             xlos(2) = xv(2,j)
             ylos(1) = yv(1,j)
             ylos(2) = yv(2,j)
             slos    = dcum(i)
          endif
        end if ! if (lback)

        ! get ready for dumping infos
        if (lbacktracking) then
           ejfvlos = ejfvLast(j)
           ejvlos = ejvLast(j)
           nucmlos = nucmLast(j)
           sigmvlos = sigmv(j)
           dpsvlos = dpsvLast(j)
           naalos = naaLast(j)
           nzzlos = nzzLast(j)
        else
           ejfvlos = ejfv(j)
           ejvlos = ejv(j)
           nucmlos = nucm(j)
           sigmvlos = sigmv(j)
           dpsvlos = dpsv(j)
           naalos = naa(j)
           nzzlos = nzz(j)
        endif

        ! ==============================================================
        ! If lost particles aren't killed, the lost info is dumped only
        ! the first time they hit the aperture. Their secondaries generated
        ! from a lost particles are considered lost as well
        if( apflag ) then
          lparID = .false.
          jjx=1
#ifdef COLLIMAT
          do jj=1,npart
#else
          do jj=1,napx
#endif
            if(plost(jj).ne.0) then
#ifdef FLUKA
              if( fluka_uid(j).eq.plost(jj).or. fluka_gen(j).eq.plost(jj) ) then
#endif
#ifdef COLLIMAT
              if( ipart(j) .eq. plost(jj) ) then
#endif
#if !defined(FLUKA) && !defined(COLLIMAT)
              if ( nlostp(j) .eq. plost(jj) ) then
#endif
                lparID=.true.
              end if

              jjx=jj+1 !points to the last zero
            end if
          end do

          if(lparID) then
            !old lost particle or secondary, don't print it
            goto 1982
          else
            !new lost particle, store ID and print it
#ifdef FLUKA
            plost(jjx) = fluka_uid(j)
#endif
#ifdef COLLIMAT
            plost(jjx) = ipart(j)
#endif
#if !defined(FLUKA) && !defined(COLLIMAT)
            plost(jjx) = j
#endif
          end if !if(lparID) then
        end if !if( apflag ) then

#ifdef HDF5
        if(h5_useForAPER) then
          call h5_prepareWrite(aper_setLostPart, 1)
          call h5_writeData(aper_setLostPart, 1,  1, turn)
          call h5_writeData(aper_setLostPart, 2,  1, i)
          call h5_writeData(aper_setLostPart, 3,  1, ix)
          call h5_writeData(aper_setLostPart, 4,  1, bez(ix))
          call h5_writeData(aper_setLostPart, 5,  1, slos)
          call h5_writeData(aper_setLostPart, 6,  1, xlos(1)*c1m3)
          call h5_writeData(aper_setLostPart, 7,  1, xlos(2)*c1m3)
          call h5_writeData(aper_setLostPart, 8,  1, ylos(1)*c1m3)
          call h5_writeData(aper_setLostPart, 9,  1, ylos(2)*c1m3)
          call h5_writeData(aper_setLostPart, 10, 1, ejfvlos*c1m3)
          call h5_writeData(aper_setLostPart, 11, 1, (ejvlos*(nucm0/nucmlos)-e0)*c1e6)
          call h5_writeData(aper_setLostPart, 12, 1, -c1m3 * (sigmvlos/clight) * (e0/e0f))
          call h5_writeData(aper_setLostPart, 13, 1, naalos)
          call h5_writeData(aper_setLostPart, 14, 1, nzzlos)
#ifdef FLUKA
          call h5_writeData(aper_setLostPart, 15, 1, fluka_uid(j))
          call h5_writeData(aper_setLostPart, 16, 1, fluka_gen(j))
          call h5_writeData(aper_setLostPart, 17, 1, fluka_weight(j))
#endif
#ifdef COLLIMAT
          call h5_writeData(aper_setLostPart, 15, 1, ipart(j))
#endif
#if !defined(FLUKA) && !defined(COLLIMAT)
          call h5_writeData(aper_setLostPart, 15, 1, nlostp(j))
#endif
          call h5_finaliseWrite(aper_setLostPart)
        else
#endif
        ! Print to unit 999 (fort.999)
#ifdef FLUKA
        write(999,'(3(1X,I8),1X,A16,1X,F12.5,2(1X,I8),8(1X,1PE14.7),2(1X,I8))')&
#else
        write(999,'(3(1X,I8),1X,A16,1X,F12.5,1X,I8,7(1X,1PE14.7),2(1X,I8))')   &
#endif

     &         turn, i, ix, bez(ix), slos,                                     &
#ifdef FLUKA
     &         fluka_uid(j), fluka_gen(j), fluka_weight(j),                    &
#endif
#ifdef COLLIMAT
     &         ipart(j),                                                       &
#endif
#if !defined(FLUKA) && !defined(COLLIMAT)
     &         nlostp(j),                                                      &
#endif

     &         xlos(1)*c1m3, ylos(1)*c1m3, xlos(2)*c1m3, ylos(2)*c1m3,         &
     &         ejfvlos*c1m3, (ejvlos*(nucm0/nucmlos)-e0)*c1e6,                 &
     &         -c1m3 * (sigmvlos/clight) * (e0/e0f),                           &
     &         naalos, nzzlos
#ifdef HDF5
        end if
#endif

#if defined(ROOT) && defined(COLLIMAT)
! root output
        if(root_flag .and. root_ApertureCheck.eq.1) then
          this_name = trim(adjustl(bez(ix))) // C_NULL_CHAR
          call ApertureCheckWriteLossParticle(turn, i, ix, this_name, len_trim(this_name), slos, ipart(j),&
       &  xlos(1)*c1m3, ylos(1)*c1m3, xlos(2)*c1m3, ylos(2)*c1m3, ejfvlos*c1m3, (ejvlos-e0)*c1e6, &
       &  -c1m3 * (sigmvlos/clight) * (e0/e0f))
        end if
#endif

#if defined(FLUKA) || defined(COLLIMAT)
        if (nlostp(j).le.aperture_napxStart) then
#endif
           pstop(nlostp(j))=.true.
           ! Record for postpr
           if (.not.limifound.or.kape(ix).eq.0) then
              aperv(nlostp(j),1) = aper(1)
              aperv(nlostp(j),2) = aper(2)
           else
              aperv(nlostp(j),1) = min(ape(1,ix),ape(3,ix))
              aperv(nlostp(j),2) = min(ape(2,ix),ape(4,ix))
           endif
           ixv(nlostp(j))     = ix
           xvl(1,nlostp(j))   = xlos(1)
           xvl(2,nlostp(j))   = xlos(2)
           yvl(1,nlostp(j))   = ylos(1)
           yvl(2,nlostp(j))   = ylos(2)
           dpsvl(nlostp(j))   = dpsvlos
           ejvl(nlostp(j))    = ejvlos
           sigmvl(nlostp(j))  = sigmvlos
           numxv(nlostp(j))   = numx
           nnumxv(nlostp(j))  = numx
#if defined(FLUKA) || defined(COLLIMAT)
        endif ! (nlostp(j).le.aperture_napxStart)
#endif

1982    continue

      end if ! if(llostp(j))
    end do ! do j=1,napx

    ! flush loss particle file
#ifdef HDF5
  if(.not. h5_useForAPER) then
#endif
    flush(999)
#ifdef HDF5
  end if
#endif

    call compactArrays(llostp)

  end if !if( llost ) then

  !-----------------------------------------------------------------------
  ! closing stuff
  !-----------------------------------------------------------------------

#ifdef FLUKA
  napxo = napx
#endif

  if(napx.eq.0) then
    write(lout,*)
    write(lout,*)
    write(lout,*) '************************'
    write(lout,*) '** ALL PARTICLES LOST **'
    write(lout,*) '**   PROGRAM STOPS    **'
    write(lout,*) '************************'
    write(lout,*)
    write(lout,*)
#ifdef FLUKA
!skip postpr
    nthinerr = 3000
#else
    nthinerr = 3001
    nnuml=numl
#endif
    return
  end if

end subroutine lostpart


logical function checkRE( x, y, apex, apey )
!-----------------------------------------------------------------------
!     A.Mereghetti and P.Garcia Ortega, for the FLUKA Team
!     last modified: 16-05-2014
!     check particle position against REctangle aperture
!     always in main code
!-----------------------------------------------------------------------
  implicit none
! parameters
  real(kind=fPrec) x, y, apex, apey
  checkRE = ( abs(x).gt.apex ).or.( abs(y).gt.apey )
  return
end function

logical function checkEL( x, y, apxx, apyy, apxy )
!-----------------------------------------------------------------------
!     A.Mereghetti and P.Garcia Ortega, for the FLUKA Team
!     last modified: 16-05-2014
!     check particle position against ELlipse aperture
!     always in main code
!-----------------------------------------------------------------------
  implicit none

! parameters
  real(kind=fPrec) x, y, apxx, apyy, apxy

  checkEL = x**two*apyy+y**two*apxx .gt. apxy
  return
end function checkEL

logical function checkRL( x, y, apex, apey, apxx, apyy, apxy )
!-----------------------------------------------------------------------
!     A.Mereghetti and P.Garcia Ortega, for the FLUKA Team
!     last modified: 16-05-2014
!     check particle position against Rect-Ellipse aperture
!     always in main code
!-----------------------------------------------------------------------
  implicit none

! parameters
  real(kind=fPrec) x, y, apex, apey, apxx, apyy, apxy

  checkRL = checkRE( x, y, apex, apey ) .or. checkEL( x, y, apxx, apyy, apxy )
  return
end function checkRL

logical function checkOC( x, y, ap1, ap2, m, q )
!-----------------------------------------------------------------------
!     A.Mereghetti and P.Garcia Ortega, for the FLUKA Team
!     last modified: 22-03-2018
!     check particle position against OCtagon aperture
!     always in main code
!-----------------------------------------------------------------------
  implicit none

! parameters
  real(kind=fPrec) x, y, ap1, ap2, m, q

  checkOC = checkRE(x,y,ap1,ap2).or.(y.gt.m*x+q)
  return
end function checkOC

logical function checkRT( x, y, apex, apey, r, r2 )
!-----------------------------------------------------------------------
!     A.Mereghetti and P.Garcia Ortega, for the FLUKA Team
!     last modified: 19-05-2014
!     check particle position against RaceTrack aperture
!     always in main code
!-----------------------------------------------------------------------
  implicit none

! parameters
  real(kind=fPrec) x, y, apex, apey, r, r2

  checkRT = checkRE( x, y, apex+r, apey+r ) .or. ( ( (abs(x)-apex)**2.+(abs(y)-apey)**2.).gt.r2 )
  return
end function checkRT

logical function checkCR( x, y, radius2 )
!-----------------------------------------------------------------------
!     check particle position against CiRcle aperture
!     always in main code
!-----------------------------------------------------------------------
  implicit none

! parameters
  real(kind=fPrec) x, y, radius2

  checkCR = (x**2 + y**2) .gt. radius2
  return
end function checkCR

logical function checkTR( x, y, aprx, apry, apex, apey, apxx, apyy, apxy, m, q )
!-----------------------------------------------------------------------
!     A.Mereghetti (CERN, BE/ABP-HSS)
!     last modified: 22-03-2018
!     check particle position against Transition aperture
!     always in main code
!-----------------------------------------------------------------------
  implicit none

! parameters
  real(kind=fPrec) x, y, aprx, apry, apex, apey, apxx, apyy, apxy, m, q

  checkTR = checkRL(x,y,aprx,apry,apxx,apyy,apxy).or.checkOC(x,y,aprx,apry,m,q)
  if (aprx-apex.gt.zero.and.apry-apey.gt.zero) checkTR=checkTR.or.checkRT(x,y,aprx,apry,apex,apxx)
  return
end function checkTR

subroutine roffpos( x, y, xnew, ynew, tlt, xoff, yoff )
!-----------------------------------------------------------------------
!     A.Mereghetti and P.Garcia Ortega, for the FLUKA Team
!     last modified: 16-05-2014
!     centre/rotate position of particles in case of offcentered/tilted
!        aperture types
!     always in main code
!
!     input parameters:
!        x : horizontal particle position [mm]
!        y : vertical   particle position [mm]
!        tlt:  tilt angle of the aperture profile [rad]
!        xoff: horizontal aperture offset [mm]
!        yoff: vertical   aperture offset [mm]
!
!     output parameters:
!        xnew : offcentered/tilted horizontal particle position [mm]
!        ynew : offcentered/tilted vertical   particle position [mm]
!
!-----------------------------------------------------------------------
  implicit none

! parameters
  real(kind=fPrec) x, y, xnew, ynew, tlt, xoff, yoff

! temporary variables
  real(kind=fPrec) theta, radio, xtmp, ytmp, ttmp

  xtmp = x+xoff
  ytmp = y+yoff
  theta = atan2_mb(ytmp, xtmp)
  radio = sqrt(xtmp**two + ytmp**two)
  ttmp = theta-tlt
  xnew = radio * cos_mb(ttmp)
  ynew = radio * sin_mb(ttmp)
  return
end subroutine roffpos

subroutine roffpos_inv( x, y, xnew, ynew, tlt, xoff, yoff )
!-----------------------------------------------------------------------
!     A.Mereghetti (CERN, BE/ABP-HSS), 2018-03-24
!     inverse of roffpos - but same interface
!-----------------------------------------------------------------------
  implicit none

! parameters
  real(kind=fPrec) x, y, xnew, ynew, tlt, xoff, yoff

! temporary variables
  real(kind=fPrec) theta, radio, ttmp

  theta = atan2_mb(y, x)
  radio = sqrt(x**two + y**two)
  ttmp = theta+tlt
  xnew = radio * cos_mb(ttmp)
  ynew = radio * sin_mb(ttmp)
  xnew = xnew-xoff
  ynew = ynew-yoff
  return
end subroutine roffpos_inv

subroutine contour_aperture_markers( itElUp, itElDw, lInsUp )
!-----------------------------------------------------------------------
! by A.Mereghetti
! last modified: 20-12-2016
! always in main code
! check elements itElUp (upstream) and itElDw (downstream) and
!   assign them (or insert) an aperture marker, in case;
! lInsUp: force the insertion of an aperture marker upstream
!   of itElUp (.false. in case of initialisation of aperture profile
!   of entire lattice, as the upstream element is the actual entry
!   in lattice sequence);
!-----------------------------------------------------------------------
  implicit none

! interface variables
  integer itElUp, itElDw
  logical lInsUp
! run time variables
  integer iElUp, iElDw, ixApeUp, ixApeDw, jj, iuold
  logical lExtremes, lsame

! do not overwrite interface variables
  iElUp=itElUp
  iElDw=itElDw
! handling extremes of lattice structure?
  lExtremes=iElUp.eq.iu.and.iElDw.eq.1

! upstream marker
  iuold=iu
  call contour_aperture_marker( iElUp, lInsUp )
! the addition of the upstream aperture marker may have
!    shifted by one the downstream entries
! NB: if lExtremes, the upstream marker is the last entry
!     in the lattice structure! Hence, no other entry is shifted!
  if( .not.lExtremes ) then
    if( iu-iuold.ne.0 ) then
      iElDw=iElDw+(iu-iuold)
      write(lout,*) '...inserted upstream marker - downstream entries shifted by',iu-iuold
    else
      write(lout,*) '...no need to insert an upstream marker - no shift of downstream entries required.'
    end if
  end if

! downstream marker
  iuold=iu
  call contour_aperture_marker( iElDw, .false. )
! the addition of the downstream aperture marker may have shifted by one the downstream entries
  if( iu-iuold.ne.0 ) then
! NB: if lExtremes, the downstream entry is the first entry
! in the lattice structure! Hence, if a new entry has been inserted,
! the upstream entry (at the end of the lattice structure) is
! shifted by 1
    if( lExtremes ) then
      iElUp=iElUp+(iu-iuold)
    end if
    write(lout,*) '...inserted downstream marker - downstream entries shifted by',iu-iuold
  else
    write(lout,*) '...no need to insert a downstream marker - no shift of downstream entries required.'
  end if

  if( lExtremes ) then
! check that the aperture markers at the extremities of accelerator
! lattice structure are the same
    ixApeUp=ic(iElUp)-nblo
    ixApeDw=ic(iElDw)-nblo
    lsame = sameAperture(ixApeUp,ixApeDw)
    if( .not.lsame ) then
      write(lout,*)' ERROR - different aperture markers at extremeties of accelerator lattice strucure'
      call dump_aperture_header( lout )
      call dump_aperture_marker( lout, ixApeUp, iElUp )
      call dump_aperture_marker( lout, ixApeDw, iElDw )
      call prror(-1)
    end if
  end if

end subroutine contour_aperture_markers

subroutine contour_aperture_marker( iEl, lInsUp )
!-----------------------------------------------------------------------
!     by A.Mereghetti
!     last modified: 20-12-2016
!     put an aperture marker at iEl
!     NB: it can be either a brand new entry in lattice sequence or
!         updating an existing one
!     interface variables:
!     - iEl: entry in lattice sequence to be checked
!     - lInsUp: if true, the new aperture marker is inserted upstream of iEl
!     always in main code
!-----------------------------------------------------------------------
#ifdef FLUKA
! import mod_fluka
! inserted in main code by the 'fluka' compilation flag
  use mod_fluka
#endif

  implicit none

! interface variables
  integer iEl
  logical lInsUp
! temporary variables
  integer i,ix,iSrcUp,iSrcDw,iApeUp,ixApeUp,iApeDw,ixApeDw,jj,itmpape,iNew,ixNew,check_SE_unique,INEESE,INEELS,ixApeNewFrom,ixEl
  real(kind=fPrec) tmpape(9), ddcum
  logical lconst,lApeUp,lApeDw,lAupDcum,lAdwDcum,lApe,lAss,lfit

! echo of input parameters
  write(lout,*) ''
  write(lout,*)' CALL TO CONTOUR_APERTURE_MARKER...'

! check upstream element
  ixEl=ic(iEl)-nblo
  if( iEl.eq.iu ) then
! end of lattice sequence: a marker might be needed
    if( ixEl.le.0 ) then
      ix=INEESE()
      iu=INEELS( 0 )
      ic(iu)=ix+nblo
      iEl=iu
      ixEl=ix
      bez(ixEl)='e.latt.aper'
      write(lout,*) ' -> inserted empty marker at end of lattice'
    end if
  else if( iEl.eq.1 ) then
! beginning of lattice sequence: a marker might be needed
    if( ixEl.le.0 ) then
      ix=INEESE()
      iu=INEELS( 1 )
      ic(1)=ix+nblo
      iEl=1
      ixEl=ix
      bez(ixEl)='s.latt.aper'
      write(lout,*)' -> inserted empty marker at start of lattice'
#ifdef FLUKA
    else if( fluka_type(ixEl).eq.FLUKA_ELEMENT.or.fluka_type(ixEl).eq.FLUKA_ENTRY   ) then
! A.Mereghetti
! last modified: 18-01-2017
! force aperture marker upstream of FLUKA_ENTRY
! inserted in main code by the 'fluka' compilation flag
      ix=INEESE()
      iu=INEELS( 1 )
      ic(1)=ix+nblo
      iEl=1
      ixEl=ix
      bez(ixEl)='s.latt.aper'
      write(lout,*) ' -> inserted empty marker at start of lattice since first entry is a FLUKA element'
#endif
    end if
  else if( ixEl.le.0 ) then
    write(lout,*) 'ERROR - lattice element at: i=',iEl
    write(lout,*) 'is NOT a SINGLE ELEMENT!'
    call prror(-1)
  end if

! echo
  write(lout,*)' look for aperture markers closest to:'
  write(lout,*)' i=',iEl,' - ix=',ixEl, ' - name: ',bez(ixEl), ' - s=',dcum(iEl)

! candidate aperture marker
  if( lInsUp ) then
    iNew=iEl-1
  else
    iNew=iEl
  end if

  ixNew=ic(iNew)-nblo
  if( iEl.eq.iu ) then
!   end of lattice sequence
    iSrcUp=iNew
    iSrcDw=1
  else if ( iEl.eq.1 ) then
!   beginning of lattice sequence:
    iSrcUp=iu
    iSrcDw=iEl
  else
    iSrcUp=iNew
    iSrcDw=iEl
  end if

! - get closest upstream aperture marker
! NB: no risk of overflow, as first/last element in lattice
! sequence should be aperture markers (and the first
! call of this function is meant to verify this assumption)
  call find_closest_aperture(iSrcUp,.true.,iApeUp,ixApeUp,lApeUp)
  if( iApeUp.eq.-1 .and. ixApeUp.eq.-1 ) then
    write(lout,*)' ERROR - could not find upstream marker'
    call prror(-1)
  end if
! - get closest downstream aperture marker
! NB: no risk of overflow, as first/last element in lattice
! sequence should be aperture markers (and the first
! call of this function is meant to verify this assumption)
  call find_closest_aperture(iSrcDw,.false.,iApeDw,ixApeDw,lApeDw)
  if( iApeDw.eq.-1 .and. ixApeDw.eq.-1 ) then
    write(lout,*)' ERROR - could not find downstream marker'
    call prror(-1)
  end if
! - echo found apertures
  call dump_aperture_header( lout )
  call dump_aperture_marker( lout, ixApeUp, iApeUp )
  call dump_aperture_marker( lout, ixApeDw, iApeDw )

! - checks:
! . iNew is iApeUp
  lApeUp=iApeUp.eq.iNew.and.ixApeUp.eq.ixNew

! . iNew is at the same s as iApeUp (inlcuding ring overvlow)
  lAupDcum=abs(dcum(iNew)-dcum(iApeUp)).lt.sPrec.or.abs(dcum(iNew)-dcum(iApeUp)-tlen).lt.sPrec

! . iNew is iApeDw
  lApeDw=iApeDw.eq.iNew.and.ixApeDw.eq.ixNew

! . iNew is at the same s as ApeDw (inlcuding ring overvlow)
  lAdwDcum=abs(dcum(iNew)-dcum(iApeDw)).lt.sPrec.or.abs(dcum(iNew)-dcum(iApeDw)-tlen).lt.sPrec

! . constant aperture?
  lconst = sameAperture( ixApeUp, ixApeDw )

! . can iNew be assigned an aperture marker?
! ie is it a single element and is it used anywhere else?
  lApe=lApeUp.or.lApeDw
  lAss=ixNew.gt.0.and.check_SE_unique(iNew,ixNew).eq.-1

! some action is needed
  if( .not.lApe ) then
! . iNew must be assigned an aperture
    ixApeNewFrom=-1
    lfit=.false.
    itmpape=0
    do jj=1,9
      tmpape(jj)=zero
    end do

!   . aperture profile
    if( lconst.or.lAupDcum ) then
!   constant aperture or upstream aperture marker at the same s-location
!   -> it is wise to use the upstream aperture
      ixApeNewFrom=ixApeUp
    else if( lAdwDcum ) then
!   same s-location as the closest downstream aperture marker
!   -> it is wise to use it!
      ixApeNewFrom=ixApeDw
    else
!   varying aperture -> we need to interpolate
      call interp_aperture( iApeUp, ixApeUp, iApeDw, ixApeDw, itmpape, tmpape, dcum(iNew) )
      lfit=.true.
    end if

!   . aperture entry
    if( .not.lAss ) then
!     ixNew cannot be assigned an aperture marker: we have to insert
!     a new entry in the lattice sequence
      if( lfit ) then
        ixNew=INEESE()
        bez(ixNew)=CrtApeName()
      end if
      iNew=iNew+1
      iu=INEELS( iNew )
    end if

!   . assign aperture profile
    if( lAss.or.lfit ) then
!     aperture model must be copied
      call copy_aperture( ixNew,ixApeNewFrom,itmpape,tmpape )
      ic(iNew)=ixNew+nblo
    else if( ixApeNewFrom.gt.-1 ) then
!     an existing aperture model can be assigned
      ic(iNew)=ixApeNewFrom+nblo
    else
!     this should never happen
      write(lout,*)' ERROR in aperture auto assignment.'
      call prror(-1)
    end if
  end if

! echo for checking
  write(lout,*) ' ...echo results of assignment:'
  call dump_aperture_header( lout )
  call dump_aperture_marker( lout, ic(iNew)-nblo, iNew )

! go home, man
  iEl=iNew
  return

 1982 format (a16,2(1x,a2),8(1x,f15.5))
end subroutine contour_aperture_marker

subroutine find_closest_aperture( iStart, lUp, iEl, ixEl, lfound )
!-----------------------------------------------------------------------
!     by A.Mereghetti (CERN, BE/ABP-HSS), 2018-03-24
!     find aperture marker closest to iStart
!-----------------------------------------------------------------------
#ifdef FLUKA
! import mod_fluka
! inserted in main code by the 'fluka' compilation flag
  use mod_fluka
#endif

  implicit none
  ! interface variables
  integer iStart, iEl, ixEl
  logical lUp, lfound
  ! temporary variables
  integer i, ix, iEnd, iStep

  iEl=-1
  ixEl=-1
  lfound=.false.

  ! search
  if (lUp) then
     iEnd=1
     iStep=-1
  else
     iEnd=iu
     iStep=1
  endif

  do i=iStart,iEnd,iStep
    ix=ic(i)-nblo
    if(ix.gt.0) then
!   SINGLE ELEMENT
#ifdef FLUKA
!     inserted in main code by the 'fluka' compilation flag
!     aperture markers should not coincide with a FLUKA element
      if( kape(ix).ne.0.and.fluka_type(ix).eq.FLUKA_NONE ) then
#else
      if( kape(ix).ne.0 ) then
#endif
        iEl=i
        ixEl=ix
        lfound=.true.
        exit
      end if
    end if
 end do
 return

end subroutine find_closest_aperture

function CrtApeName() result(retValue)
!-----------------------------------------------------------------------
!     by A.Mereghetti (CERN, BE/ABP-HSS)
!     last modified: 01-12-2016
!     Create Aperture Name
!     always in main code
!-----------------------------------------------------------------------
  implicit none

  character(len=max_name_len) retValue
  integer iApe, ii
  data iApe / 0 /
  save iApe

  iApe=iApe+1
  write(retValue, "(A10,I6)") "auto.aper.", iApe

  do ii=11,16
    if( retValue(ii:ii) .eq. ' ' ) retValue(ii:ii)='0'
  end do

end function CrtApeName

logical function sameAperture( ixApeUp, ixApeDw )
!-----------------------------------------------------------------------
!     by A.Mereghetti (CERN, BE/ABP-HSS)
!     last modified: 21-03-2018
!     Verify that two aperture markers actually describe the same aperture
!       restriction
!-----------------------------------------------------------------------
  implicit none
  integer ixApeUp, ixApeDw, jj
  sameAperture=ixApeDw.eq.ixApeUp.or.kape(ixApeDw).eq.kape(ixApeUp)
  if (sameAperture) then
     do jj=1,9
        sameAperture=sameAperture.and.abs(ape(jj,ixApeDw)-ape(jj,ixApeUp)).lt.aPrec
        if (.not.sameAperture) exit
     end do
  end if
end function sameAperture

subroutine interp_aperture( iUp,ixUp, iDw,ixDw, oKApe,oApe, spos )
!-----------------------------------------------------------------------
!     by A.Mereghetti
!     last modified: 21-03-2018
!     interpolate aperture
!     always in main code
!-----------------------------------------------------------------------
  implicit none

! interface variables
  integer iUp, ixUp, iDw, ixDw, oKApe
  real(kind=fPrec) oApe(9), spos
! temporary variables
  real(kind=fPrec) ddcum, mdcum
  integer jj

  if( sameAperture(ixUp,ixDw ) ) then
     ! constant aperture - no need to interpolate
     oKApe=kape(ixUp)
     do jj=1,9
        oApe(jj)=ape(jj,ixUp)
     end do
  else
     ! non-constant aperture - interpolate
     ! type: we may interpolate the same aperture type
     oKApe=-1 ! transition
     if ( kape(ixUp).eq.kape(ixDw) ) oKApe=kape(ixUp)

     ! actual interpolation
     ddcum = spos-dcum(iUp)
     if( ddcum.lt.zero ) ddcum=tlen+ddcum
     mdcum = dcum(iDw)-dcum(iUp)
     if( mdcum.lt.zero ) mdcum=tlen+mdcum
     do jj=1,9
        oApe(jj)=(ape(jj,ixDw)-ape(jj,ixUp))/mdcum*ddcum+ape(jj,ixUp)
     end do
  end if
  return
end subroutine interp_aperture

subroutine copy_aperture( ixApeTo, ixApeFrom, nKApe, nApe )
!-----------------------------------------------------------------------
!     by A.Mereghetti
!     last modified: 02-12-2016
!     copy aperture, either from an existing one or from the one
!       received on the fly
!     always in main code
!-----------------------------------------------------------------------
  implicit none

! interface variables
  integer ixApeTo, ixApeFrom, nKApe
  real(kind=fPrec) nApe(9)
! temporary variables
  integer jj

  if( ixApeFrom.gt.0 ) then
! copy aperture marker from existing SINGLE ELEMENT
    kape(ixApeTo)=kape(ixApeFrom)
    do jj=1,9
      ape(jj,ixApeTo)=ape(jj,ixApeFrom)
    end do
  else
! copy aperture marker from temporary one
    kape(ixApeTo)=nKApe
    do jj=1,9
      ape(jj,ixApeTo)=nApe(jj)
    end do
  end if

end subroutine copy_aperture

subroutine dump_aperture_model
!-----------------------------------------------------------------------
!     by P.Garcia Ortega, for the FLUKA Team, and A.Mereghetti
!     last modified: 08-12-2016
!     dump all apertures declared in machine
!     always in main code
!-----------------------------------------------------------------------
  implicit none

! temporary variables
  integer i, ix
  logical lopen

  integer iOld, ixOld, niter, oKApe, jj
  real(kind=fPrec) aprr(9),slos
  character(len=max_name_len), parameter :: interpolated = 'interpolated'

  write(lout,*)''
  write(lout,fmt="(131('-'))")
  write(lout,*)''
  write(lout,*)' DUMP OF APERTURE MODEL'
  write(lout,*)''

  inquire( unit=aperunit, opened=lopen )
  if( .not.lopen ) then
    if( aperunit.ne.0 ) then
       open( aperunit, file=aper_filename, form='formatted' )
       write(lout,*) 'APERTURE PROFILE DUMPED IN FILE: ',aper_filename,' - UNIT: ',aperunit
    end if
  end if

! Header
  call dump_aperture_header( aperunit )

! First element of lattice
  i=1
  ix=ic(i)-nblo
  if( kape(ix).eq.0 ) then
    write(lout,*) ' ERROR - first element of lattice structure is not assigned any aperture type'
    call prror(-1)
  end if
  call dump_aperture_marker( aperunit, ix, i )
  iOld=i
  ixOld=ix

  do i=2,iu
    ix=ic(i)-nblo
    if(ix.gt.0) then
      ! SINGLE ELEMENT
      if( kape(ix) .ne. 0 ) then
        if (lbacktracking) then
          ! Number of iterations
          if( (dcum(i)-dcum(iOld)).gt.zero) then
            niter = nint((dcum(i)-dcum(iOld))/bktpre+1)
            do jj=1,niter
              slos = int(dcum(iOld)/bktpre+jj)*bktpre
              if ( slos.lt.dcum(iOld) .or. slos.gt.dcum(i) ) exit
              call interp_aperture(iOld,ixOld,i,ix,oKApe,aprr,slos)
              call dump_aperture( aperunit, interpolated, oKApe, slos, aprr )
            end do
          end if
          iOld=i
          ixOld=ix
        endif
        call dump_aperture_marker( aperunit, ix, i )
      end if
    end if
  end do

  return

end subroutine dump_aperture_model

subroutine dumpMe
  implicit none

! temporary variables
  integer i, ix

  write(lout,*) 'dumpMe - start'
  do i=1,iu
    ix=ic(i)-nblo
    if( ix.gt.0 ) then
      write(lout,*) i,bez(ix),dcum(i),kape(ix)
    else
      write(lout,*) i,bezb(ic(i)),dcum(i)
    end if
  end do

  write(lout,*) 'dumpMe - end'

end subroutine dumpMe

subroutine dump_aperture( iunit, name, aptype, spos, ape )
!-----------------------------------------------------------------------
!     by A.Mereghetti
!     last modified: 08-12-2016
!     dump any aperture marker
!     always in main code
!-----------------------------------------------------------------------
  implicit none

! interface variables
  integer iunit
  integer aptype
  character(len=max_name_len) name
  real(kind=fPrec) ape(9)
  real(kind=fPrec) spos

! dump info
  if (ldmpaperMem) then
     write(iunit,1984) name, apeName(aptype), spos, ape(1), ape(2), ape(3), ape(4), ape(5), ape(6), ape(7), ape(8), ape(9)
  else
     select case(aptype)
     case(-1) ! transition
        write(iunit,1984) name, apeName(aptype), spos, ape(1), ape(2), ape(3), ape(4), ape(5), ape(6), ape(7), ape(8), ape(9)
     case(0) ! not an aperture marker
        write(iunit,1984) name, apeName(aptype), spos, ape(1), ape(2), ape(3), ape(4), ape(5), ape(6), ape(7), ape(8), ape(9)
     case(1) ! Circle
        write(iunit,1984) name, apeName(aptype), spos, ape(1),   zero,   zero,   zero,   zero,   zero, ape(7), ape(8), ape(9)
     case(2) ! Rectangle
        write(iunit,1984) name, apeName(aptype), spos, ape(1), ape(2),   zero,   zero,   zero,   zero, ape(7), ape(8), ape(9)
     case(3) ! Ellipse
        write(iunit,1984) name, apeName(aptype), spos, ape(3), ape(4),   zero,   zero,   zero,   zero, ape(7), ape(8), ape(9)
     case(4) ! Rectellipse
        write(iunit,1984) name, apeName(aptype), spos, ape(1), ape(2), ape(3), ape(4),   zero,   zero, ape(7), ape(8), ape(9)
     case(5) ! Octagon
        ! get angles from points passing through x1,y1 and x2,y2
        ! x1=ape(1)
        ! y1=ape(1)*tan(theta1)
        ! x2=ape(2)/tan(theta2)
        ! y2=ape(2)
        write(iunit,1984) name, apeName(aptype), spos, ape(1), ape(2), atan2_mb(ape(1)*ape(5)+ape(6),ape(1)), &
             &         atan2_mb(ape(2),(ape(2)-ape(6))/ape(5)),   zero,   zero, ape(7), ape(8), ape(9)
     case(6) ! Racetrack
        write(iunit,1984) name, apeName(aptype), spos, ape(1), ape(2), ape(3),   zero,   zero,   zero, ape(7), ape(8), ape(9)
     end select
  end if
  return
 1984 format (1x,a16,1x,a6,10(1x,f15.5))
end subroutine dump_aperture

subroutine dump_aperture_marker( iunit, ixEl, iEl )
!-----------------------------------------------------------------------
!     by A.Mereghetti
!     last modified: 08-12-2016
!     dump single aperture marker, existing in aperture DB
!     always in main code
!-----------------------------------------------------------------------
  implicit none

! interface variables
  integer iunit, iEl, ixEl

  call dump_aperture( iunit, bez(ixEl), kape(ixEl), dcum(iEl), ape(1:9,ixEl) )

  return
end subroutine dump_aperture_marker

subroutine dump_aperture_header( iunit )
!-----------------------------------------------------------------------
!     by A.Mereghetti
!     last modified: 22-03-2018
!     dump header of aperture marker
!     always in main code
!-----------------------------------------------------------------------
  implicit none
  integer iunit
  write(iunit,1984) '#', 'name', 'aptype', 's[m]', 'aper1[mm]', 'aper2[mm]', &
 &                  'aper3[mm][rad]', 'aper4[mm][rad]', 'aper5[mm][rad]', 'aper6[mm][rad]', &
 &                  'angle[rad]', 'xoff[mm]', 'yoff[mm]'
  return
 1984 format (a1,a16,1x,a6,1x,10(1x,a15))
end subroutine dump_aperture_header

subroutine dump_aperture_xsecs
  !-----------------------------------------------------------------------
  ! A.Mereghetti (CERN, BE/ABP-HSS), 22-03-2018
  ! dump cross-sections of apertures at specific locations (loop)
  !-----------------------------------------------------------------------
  implicit none
  ! temporary variables
  logical lfound, lopen, lApeUp, lApeDw
  integer ixsec, ierro, iEl, ixEl, iApeUp, ixApeUp, iApeDw, ixApeDw, itmpape
  real(kind=fPrec) sLoc, tmpape(9)

  ! loop over requested lines
  do ixsec=1,mxsec
     ! from print_lastlines_to_stderr
     inquire(unit=xsecunit(ixsec),opened=lopen)
     if (lopen) then
        write(lout,*)'Dump_aperture_xsecs - Error in opening unit ',xsecunit(ixsec), &
 &            ' - filename: ',xsec_filename(ixsec),' - the file is already open.'
        call prror(-1)
     end if
     open(unit=xsecunit(ixsec),file=xsec_filename(ixsec),form="formatted",status="old",iostat=ierro)
     if (ierro .ne. 0) then
        write(lout,'(a,a,a,1x,i5,1x,a,1x,i5)')                         &
     &        "Error when opening file '",                             &
     &        trim(xsec_filename(ixsec)),                              &
     &        "' on unit #", xsecunit(ixsec), ", iostat =",ierro
        call prror(-1)
     endif

     ! loop over s-locations
     sLoc=sLocMin(ixsec)
     do while(sLoc.le.sLocMax(ixsec))
        call find_entry_at_s( sLoc, .true., iEl, ixEl, lfound )
        if (.not.lfound) call prror(-1)
        ! get upstream aperture marker
        call find_closest_aperture(iEl,.true.,iApeUp,ixApeUp,lApeUp)
        if( iApeUp.eq.-1 .and. ixApeUp.eq.-1 ) then
           write(lout,*)' ERROR - could not find upstream aperture marker'
           call prror(-1)
        end if
        ! get downstream aperture marker
        call find_closest_aperture(iEl,.false.,iApeDw,ixApeDw,lApeDw)
        if( iApeDw.eq.-1 .and. ixApeDw.eq.-1 ) then
           write(lout,*)' ERROR - could not find downstream aperture marker'
           call prror(-1)
        end if
        ! interpolate and get aperture at desired location
        call interp_aperture( iApeUp, ixApeUp, iApeDw, ixApeDw, itmpape, tmpape, sLoc )
        ! dump the x-sec of the aperture
        call dump_aperture_xsec(xsecunit(ixsec),itmpape,tmpape,nAzimuts(ixsec),sLoc)
        sLoc=sLoc+sLocDel(ixsec)
     enddo

     close(xsecunit(ixsec))
  enddo

  return
end subroutine dump_aperture_xsecs


subroutine dump_aperture_xsec( iunit, itmpape, tmpape, nAzim, sLoc )
  !-----------------------------------------------------------------------
  ! A.Mereghetti (CERN, BE/ABP-HSS), 22-03-2018
  ! dump the cross-sections of the machine aperture at a specific location
  !-----------------------------------------------------------------------
  implicit none
  ! interface variables
  integer iunit, itmpape, nAzim
  real(kind=fPrec) tmpape(9), sLoc
  ! temporary variables
  logical tmpOffTlt
  integer i
  real(kind=fPrec) xChk, yChk, nChk, thetaRay, xRay, yRay

  write(iunit,*)'# aperture at s=',sLoc
  write(iunit,*)'# type:',itmpape
  write(iunit,*)'# specifiers:'
  do i=1,9
     write(iunit,*)'# - ape(',i,')=',tmpape(i)
  enddo
  write(iunit,*)'# number of points:',nAzim
  write(iunit,1981) '# ang[deg]', 'rad [mm]', 'x [mm]', 'y [mm]'
  tmpOffTlt=tmpape(7).ne.zero.or.tmpape(8).ne.zero.or.tmpape(9).ne.zero

  ! origin of ray:
  xRay=zero
  yRay=zero
  if (tmpOffTlt) call roffpos(xRay,yRay,xRay,yRay,tmpape(7),tmpape(8),tmpape(9))

  ! loop over rays
  select case(itmpape)
  case(-1) ! transition
     do i=1,nAzim
        thetaRay=i/real(nAzim)*two*pi ! radians
        ! call (angle to aperture ref sys)
        call intersectTR(xRay,yRay,thetaRay-tmpape(7),tmpape(1),tmpape(2),tmpape(3),tmpape(4),tmpape(5),tmpape(6),xChk,yChk,nChk)
        ! go back to machine reference system
        if (tmpOffTlt) call roffpos_inv(xChk,yChk,xChk,yChk,tmpape(7),tmpape(8),tmpape(9))
        ! echo result of scan
        write(iunit,1982) thetaRay/pi*180_fPrec,sqrt(xChk**2+yChk**2),xChk,yChk
     enddo
  case(1) ! circle
     do i=1,nAzim
        thetaRay=i/real(nAzim)*two*pi ! radians
        ! call (angle to aperture ref sys)
        call intersectCR(xRay,yRay,thetaRay-tmpape(7),tmpape(3),zero,zero,xChk,yChk,nChk)
        ! go back to machine reference system
        if (tmpOffTlt) call roffpos_inv(xChk,yChk,xChk,yChk,tmpape(7),tmpape(8),tmpape(9))
        ! echo result of scan
        write(iunit,1982) thetaRay/pi*180_fPrec,sqrt(xChk**2+yChk**2),xChk,yChk
     enddo
  case(2) ! rectangle
     do i=1,nAzim
        thetaRay=i/real(nAzim)*two*pi ! radians
        ! call (angle to aperture ref sys)
        call intersectRE(xRay,yRay,thetaRay-tmpape(7),tmpape(1),tmpape(2),xChk,yChk,nChk)
        ! go back to machine reference system
        if (tmpOffTlt) call roffpos_inv(xChk,yChk,xChk,yChk,tmpape(7),tmpape(8),tmpape(9))
        ! echo result of scan
        write(iunit,1982) thetaRay/pi*180_fPrec,sqrt(xChk**2+yChk**2),xChk,yChk
     enddo
  case(3) ! ellipse
     do i=1,nAzim
        thetaRay=i/real(nAzim)*two*pi ! radians
        ! call (angle to aperture ref sys)
        call intersectEL(xRay,yRay,thetaRay-tmpape(7),tmpape(3),tmpape(4),zero,zero,xChk,yChk,nChk)
        ! go back to machine reference system
        if (tmpOffTlt) call roffpos_inv(xChk,yChk,xChk,yChk,tmpape(7),tmpape(8),tmpape(9))
        ! echo result of scan
        write(iunit,1982) thetaRay/pi*180_fPrec,sqrt(xChk**2+yChk**2),xChk,yChk
     enddo
  case(4) ! rectellipse
     do i=1,nAzim
        thetaRay=i/real(nAzim)*two*pi ! radians
        ! call (angle to aperture ref sys)
        call intersectRL(xRay,yRay,thetaRay-tmpape(7),tmpape(1),tmpape(2),tmpape(3),tmpape(4),xChk,yChk,nChk)
        ! go back to machine reference system
        if (tmpOffTlt) call roffpos_inv(xChk,yChk,xChk,yChk,tmpape(7),tmpape(8),tmpape(9))
        ! echo result of scan
        write(iunit,1982) thetaRay/pi*180_fPrec,sqrt(xChk**2+yChk**2),xChk,yChk
     enddo
  case(5) ! octagon
     do i=1,nAzim
        thetaRay=i/real(nAzim)*two*pi ! radians
        ! call (angle to aperture ref sys)
        call intersectOC(xRay,yRay,thetaRay-tmpape(7),tmpape(1),tmpape(2),tmpape(5),tmpape(6),xChk,yChk,nChk)
        ! go back to machine reference system
        if (tmpOffTlt) call roffpos_inv(xChk,yChk,xChk,yChk,tmpape(7),tmpape(8),tmpape(9))
        ! echo result of scan
        write(iunit,1982) thetaRay/pi*180_fPrec,sqrt(xChk**2+yChk**2),xChk,yChk
     enddo
  case(6) ! racetrack
     do i=1,nAzim
        thetaRay=i/real(nAzim)*two*pi ! radians
        ! call (angle to aperture ref sys)
        call intersectRT(xRay,yRay,thetaRay-tmpape(7),tmpape(1),tmpape(2),tmpape(3),xChk,yChk,nChk)
        ! go back to machine reference system
        if (tmpOffTlt) call roffpos_inv(xChk,yChk,xChk,yChk,tmpape(7),tmpape(8),tmpape(9))
        ! echo result of scan
        write(iunit,1982) thetaRay/pi*180_fPrec,sqrt(xChk**2+yChk**2),xChk,yChk
     enddo
  end select
  write(iunit,*)''
  write(iunit,*)''
  return
1981 FORMAT(1(1X,a10))
1982 FORMAT(4(1x,f10.5))

end subroutine dump_aperture_xsec

subroutine intersectCR( xRay, yRay, thetaRay, radius, x0, y0, xChk, yChk, nChk )
  ! 0.0<=thetaRay<=2pi!!!!!
  implicit none
  ! interface variables
  real(kind=fPrec) xRay, yRay, thetaRay, radius, x0, y0, xChk, yChk, nChk
  ! temp variables
  real(kind=fPrec) mRay, qRay, delta, tmpX0, tmpY0

  ! scanning ray:
  xChk=c1e3
  yChk=c1e3
  nChk=c1e3
  mRay=zero
  qRay=zero
  if (abs(thetaRay).lt.c1m6.or.abs(thetaRay/(two*pi)-one).lt.c1m6) then ! thetaRay=0.0 or thetaRay=2pi
     yChk=zero
     xChk=radius
  elseif (abs(thetaRay/(pi/two)-one).lt.c1m6) then ! thetaRay=0.5pi
     yChk=radius
     xChk=zero
  elseif (abs(thetaRay/pi-one).lt.c1m6) then ! thetaRay=pi
     yChk=zero
     xChk=-radius
  elseif (abs(thetaRay/(pi*three/two)-one).lt.c1m6) then ! thetaRay=1.5pi
     yChk=-radius
     xChk=zero
  else
     mRay=tan_mb(thetaRay)
     qRay=yRay-mRay*xRay
     if (zero.lt.thetaRay.and.thetaRay.lt.pi/two) then ! first quadrant
        tmpX0=abs(x0)
        tmpY0=abs(y0)
     elseif (pi/two.lt.thetaRay.and.thetaRay.lt.pi) then ! second quadrant
        tmpX0=-abs(x0)
        tmpY0=abs(y0)
     elseif (pi.lt.thetaRay.and.thetaRay.lt.pi/two*three) then ! second quadrant
        tmpX0=-abs(x0)
        tmpY0=-abs(y0)
     else ! fourth quadrant
        tmpX0=abs(x0)
        tmpY0=-abs(y0)
     endif
     delta=-(mRay*tmpX0-tmpY0+qRay)**2+radius**2*(one+mRay**2)
     if (delta.lt.zero) return
     if ((zero.lt.thetaRay.and.thetaRay.lt.pi/two) .or. & ! first quadrant
 &       (pi/two*three.lt.thetaRay.and.thetaRay.lt.two*pi)) then ! fourth quadrant
        xChk=(tmpX0+mRay*(tmpY0-qRay)+sqrt(delta))/(one+mRay**2)
     else
        xChk=(tmpX0+mRay*(tmpY0-qRay)-sqrt(delta))/(one+mRay**2)
     endif
     yChk=mRay*xChk+qRay
  endif
  nChk=radius
  return
end subroutine intersectCR

subroutine intersectRE( xRay, yRay, thetaRay, xRe, yRe, xChk, yChk, nChk )
  ! 0.0<=thetaRay<=2pi!!!!!
  implicit none
  ! interface variables
  real(kind=fPrec) xRay, yRay, thetaRay, xRe, yRe, xChk, yChk, nChk
  ! temp variables
  real(kind=fPrec) mRay, qRay, xTmp(2), yTmp(2), nTmp(2)

  ! scanning ray:
  xChk=zero
  yChk=zero
  nChk=zero
  mRay=zero
  qRay=zero
  if (abs(thetaRay).lt.c1m6.or.abs(thetaRay/(two*pi)-one).lt.c1m6) then ! thetaRay=0.0 or thetaRay=2pi
     yChk=zero
     xChk=xRe
     nChk=xRe
  elseif (abs(thetaRay/(pi/two)-one).lt.c1m6) then ! thetaRay=0.5pi
     yChk=yRe
     xChk=zero
     nChk=yRe
  elseif (abs(thetaRay/pi-one).lt.c1m6) then ! thetaRay=pi
     yChk=zero
     xChk=-xRe
     nChk=xRe
  elseif (abs(thetaRay/(pi*three/two)-one).lt.c1m6) then ! thetaRay=1.5pi
     yChk=-yRe
     xChk=zero
     nChk=yRe
  else
     mRay=tan_mb(thetaRay)
     qRay=yRay-mRay*xRay
     if (zero.lt.thetaRay.and.thetaRay.lt.pi/two) then ! first quadrant
        xTmp(1)=xRe
        yTmp(2)=yRe
     elseif (pi/two.lt.thetaRay.and.thetaRay.lt.pi) then ! second quadrant
        xTmp(1)=-xRe
        yTmp(2)=yRe
     elseif (pi.lt.thetaRay.and.thetaRay.lt.pi/two*three) then ! third quadrant
        xTmp(1)=-xRe
        yTmp(2)=-yRe
     else ! fourth quadrant
        xTmp(1)=xRe
        yTmp(2)=-yRe
     endif
     yTmp(1)=mRay*xTmp(1)+qRay
     xTmp(2)=(yTmp(2)-qRay)/mRay
     nTmp(1)=xTmp(1)**2+yTmp(1)**2
     nTmp(2)=xTmp(2)**2+yTmp(2)**2
     if (nTmp(1).lt.nTmp(2)) then
        xChk=xTmp(1)
        yChk=yTmp(1)
     else
        xChk=xTmp(2)
        yChk=yTmp(2)
     endif
     nChk=sqrt(xChk**2+yChk**2)
  endif
  return
end subroutine intersectRE

subroutine intersectEL( xRay, yRay, thetaRay, aa, bb, x0, y0, xChk, yChk, nChk )
  ! 0.0<=thetaRay<=2pi!!!!!
  implicit none
  ! interface variables
  real(kind=fPrec) xRay, yRay, thetaRay, aa, bb, x0, y0, xChk, yChk, nChk
  ! temp variables
  real(kind=fPrec) mRay, qRay, delta, tmpX0, tmpY0

  ! scanning ray:
  xChk=c1e3
  yChk=c1e3
  nChk=c1e3
  mRay=zero
  qRay=zero
  if (abs(thetaRay).lt.c1m6.or.abs(thetaRay/(two*pi)-one).lt.c1m6) then ! thetaRay=0.0 or thetaRay=2pi
     yChk=zero
     xChk=aa
     nChk=aa
  elseif (abs(thetaRay/(pi/two)-one).lt.c1m6) then ! thetaRay=0.5pi
     yChk=bb
     xChk=zero
     nChk=bb
  elseif (abs(thetaRay/pi-one).lt.c1m6) then ! thetaRay=pi
     yChk=zero
     xChk=-aa
     nChk=aa
  elseif (abs(thetaRay/(pi*three/two)-one).lt.c1m6) then ! thetaRay=1.5pi
     yChk=-bb
     xChk=zero
     nChk=bb
  else
     mRay=tan_mb(thetaRay)
     qRay=yRay-mRay*xRay
     if (zero.lt.thetaRay.and.thetaRay.lt.pi/two) then ! first quadrant
        tmpX0=abs(x0)
        tmpY0=abs(y0)
     elseif (pi/two.lt.thetaRay.and.thetaRay.lt.pi) then ! second quadrant
        tmpX0=-abs(x0)
        tmpY0=abs(y0)
     elseif (pi.lt.thetaRay.and.thetaRay.lt.pi/two*three) then ! second quadrant
        tmpX0=-abs(x0)
        tmpY0=-abs(y0)
     else ! fourth quadrant
        tmpX0=abs(x0)
        tmpY0=-abs(y0)
     endif
     delta=-(mRay*tmpX0-tmpY0+qRay)**2+(bb**2+aa**2*mRay**2)
     if (delta.lt.zero) return
     if ((zero.lt.thetaRay.and.thetaRay.lt.pi/two).or. & ! first quadrant
 &       (pi/two*three.lt.thetaRay.and.thetaRay.lt.two*pi)) then ! fourth quadrant
        xChk=(aa**2*mRay*(tmpY0-qRay)+bb**2*tmpX0+aa*bb*sqrt(delta))/(bb**2+aa**2*mRay**2)
     else
        xChk=(aa**2*mRay*(tmpY0-qRay)+bb**2*tmpX0-aa*bb*sqrt(delta))/(bb**2+aa**2*mRay**2)
     endif
     yChk=mRay*xChk+qRay
     nChk=sqrt(xChk**2+yChk**2)
  endif
  return
end subroutine intersectEL

subroutine intersectRL( xRay, yRay, thetaRay, xRe, yRe, aa, bb, xChk, yChk, nChk )
  ! 0.0<=thetaRay<=2pi!!!!!
  implicit none
  ! interface variables
  real(kind=fPrec) xRay, yRay, thetaRay, xRe, yRe, aa, bb, xChk, yChk, nChk
  ! temp variables
  real(kind=fPrec) xTmp(2), yTmp(2), nTmp(2)
  call intersectRE( xRay, yRay, thetaRay, xRe, yRe, xTmp(1), yTmp(1), nTmp(1) )
  call intersectEL( xRay, yRay, thetaRay, aa, bb, zero, zero, xTmp(2), yTmp(2), nTmp(2) )
  if (nTmp(1).lt.nTmp(2)) then
     xChk=xTmp(1)
     yChk=yTmp(1)
     nChk=nTmp(1)
  else
     xChk=xTmp(2)
     yChk=yTmp(2)
     nChk=nTmp(2)
  endif
  return
end subroutine intersectRL

subroutine intersectLN( xRay, yRay, thetaRay, mLine, qLine, xChk, yChk, nChk )
  ! 0.0<=thetaRay<=2pi!!!!!
  implicit none
  ! interface variables
  real(kind=fPrec) xRay, yRay, thetaRay, mLine, qLine, xChk, yChk, nChk
  ! temp variables
  real(kind=fPrec) mRay, qRay, mTmp, qTmp

  ! scanning ray:
  xChk=zero
  yChk=zero
  nChk=zero
  mRay=zero
  qRay=zero
  mTmp=zero
  qTmp=zero
  if (abs(thetaRay).lt.c1m6.or.abs(thetaRay/(two*pi)-one).lt.c1m6) then ! thetaRay=0.0 or thetaRay=2pi
     yChk=zero
     xChk=-qLine/mLine
     nChk=abs(qLine/mLine)
  elseif (abs(thetaRay/(pi/two)-one).lt.c1m6) then ! thetaRay=0.5pi
     yChk=qLine
     xChk=zero
     nChk=abs(qLine)
  elseif (abs(thetaRay/pi-one).lt.c1m6) then ! thetaRay=pi
     yChk=zero
     xChk=qLine/mLine
     nChk=abs(qLine/mLine)
  elseif (abs(thetaRay/(pi*three/two)-one).lt.c1m6) then ! thetaRay=1.5pi
     yChk=-qLine
     xChk=zero
     nChk=abs(qLine)
  else
     mRay=tan_mb(thetaRay)
     qRay=yRay-mRay*xRay
     if (zero.lt.thetaRay.and.thetaRay.lt.pi/two) then ! first quadrant
        mTmp=mLine
        qTmp=qLine
     elseif (pi/two.lt.thetaRay.and.thetaRay.lt.pi) then ! second quadrant
        mTmp=-mLine
        qTmp=qLine
     elseif (pi.lt.thetaRay.and.thetaRay.lt.pi/two*three) then ! third quadrant
        mTmp=mLine
        qTmp=-qLine
     else ! fourth quadrant
        mTmp=-mLine
        qTmp=-qLine
     endif
     xChk=-(qRay-qLine)/(mRay-mLine)
     yChk=mRay*xChk+qRay
     nChk=sqrt(xChk**2+yChk**2)
  endif
  return
end subroutine intersectLN

subroutine intersectOC( xRay, yRay, thetaRay, xRe, yRe, mOct, qOct, xChk, yChk, nChk )
  ! 0.0<=thetaRay<=2pi!!!!!
  use numerical_constants
  implicit none
  ! interface variables
  real(kind=fPrec) xRay, yRay, thetaRay, xRe, yRe, mOct, qOct, xChk, yChk, nChk
  ! temp variables
  real(kind=fPrec) xTmp(2), yTmp(2), nTmp(2)
  call intersectRE( xRay, yRay, thetaRay,  xRe,  yRe, xTmp(1), yTmp(1), nTmp(1) )
  call intersectLN( xRay, yRay, thetaRay, mOct, qOct, xTmp(2), yTmp(2), nTmp(2) )
  ! octagon part
  if (nTmp(1).lt.nTmp(2)) then
     xChk=xTmp(1)
     yChk=yTmp(1)
     nChk=nTmp(1)
  else
     xChk=xTmp(2)
     yChk=yTmp(2)
     nChk=nTmp(2)
  endif
  return
end subroutine intersectOC

subroutine intersectRT( xRay, yRay, thetaRay, xRe, yRe, radius, xChk, yChk, nChk )
  ! 0.0<=thetaRay<=2pi!!!!!
  implicit none
  ! interface variables
  real(kind=fPrec) xRay, yRay, thetaRay, xRe, yRe, radius, xChk, yChk, nChk
  ! temp variables
  real(kind=fPrec) xTmp(2), yTmp(2), nTmp(2)
  call intersectRE( xRay, yRay, thetaRay, xRe, yRe, xTmp(1), yTmp(1), nTmp(1) )
  call intersectCR( xRay, yRay, thetaRay, radius, xRe-radius, yRe-radius, xTmp(2), yTmp(2), nTmp(2) )
  if (nTmp(1).lt.nTmp(2)) then
     xChk=xTmp(1)
     yChk=yTmp(1)
     nChk=nTmp(1)
  else
     xChk=xTmp(2)
     yChk=yTmp(2)
     nChk=nTmp(2)
  endif
  return
end subroutine intersectRT

subroutine intersectTR( xRay, yRay, thetaRay, xRe, yRe, aa, bb, mOct, qOct, xChk, yChk, nChk )
  ! 0.0<=thetaRay<=2pi!!!!!
  implicit none
  ! interface variables
  real(kind=fPrec) xRay, yRay, thetaRay, xRe, yRe, aa, bb, mOct, qOct, xChk, yChk, nChk
  ! temp variables
  real(kind=fPrec) xTmp(2), yTmp(2), nTmp(2)
  call intersectRE( xRay, yRay, thetaRay, xRe, yRe, xTmp(1), yTmp(1), nTmp(1) )
  call intersectEL( xRay, yRay, thetaRay, aa, bb, xRe-aa, yRe-bb, xTmp(2), yTmp(2), nTmp(2) )
  if (nTmp(1).gt.nTmp(2)) then
     xTmp(1)=xTmp(2)
     yTmp(1)=yTmp(2)
     nTmp(1)=nTmp(2)
  endif
  call intersectLN( xRay, yRay, thetaRay, mOct, qOct, xTmp(2), yTmp(2), nTmp(2) )
  if (nTmp(1).lt.nTmp(2)) then
     xChk=xTmp(1)
     yChk=yTmp(1)
     nChk=nTmp(1)
  else
     xChk=xTmp(2)
     yChk=yTmp(2)
     nChk=nTmp(2)
  endif
  return
end subroutine intersectTR


!>
!! compactArrays(llostp)
!! This routine is called to compact all relevant arrays when a particle is lost
!<
subroutine compactArrays(llostp)

#ifdef FLUKA
  use mod_fluka
#endif

#ifdef COLLIMAT
  use collimation
#endif

  implicit none

  integer j,jj,jj1,ib2,ib3,lnapx
  logical llostp(npart)

  ! Compact array
  if(.not.apflag) then
    lnapx=napx
    do j=napx,1,-1
      if(llostp(j)) then
        if(j.ne.lnapx) then
          do jj=j,lnapx-1
            jj1=jj+1
            nlostp(jj)=nlostp(jj1)
            xv(1,jj)=xv(1,jj1)
            xv(2,jj)=xv(2,jj1)
            yv(1,jj)=yv(1,jj1)
            yv(2,jj)=yv(2,jj1)
            dpsv(jj)=dpsv(jj1)
            sigmv(jj)=sigmv(jj1)
            ejfv(jj)=ejfv(jj1)
            ejv(jj)=ejv(jj1)
            rvv(jj)=rvv(jj1)
! ph: hisix
            nzz(jj)=nzz(jj1)
            naa(jj)=naa(jj1)
            nucm(jj)=nucm(jj1)
            mtc(jj)=mtc(jj1)
            moidpsv(jj)=moidpsv(jj1)
            omoidpsv(jj)=omoidpsv(jj1)
! ph: hisix
            oidpsv(jj)=oidpsv(jj1)
            dpsv1(jj)=dpsv1(jj1)
            clo6v(1,jj)=clo6v(1,jj1)
            clo6v(2,jj)=clo6v(2,jj1)
            clo6v(3,jj)=clo6v(3,jj1)
            clop6v(1,jj)=clop6v(1,jj1)
            clop6v(2,jj)=clop6v(2,jj1)
            clop6v(3,jj)=clop6v(3,jj1)

            !--beam-beam element
            di0xs(jj)=di0xs(jj1)
            dip0xs(jj)=dip0xs(jj1)
            di0zs(jj)=di0zs(jj1)
            dip0zs(jj)=dip0zs(jj1)
            do ib2=1,6
              do ib3=1,6
                tasau(jj,ib2,ib3)=tasau(jj1,ib2,ib3)
              end do
            end do

#ifdef COLLIMAT
! If collimation is enabled, all the collimation arrays must also be compressed
            part_hit_pos(jj)   = part_hit_pos(jj1)
            part_hit_turn(jj)  = part_hit_turn(jj1)
            part_abs_pos(jj)   = part_abs_pos(jj1)
            part_abs_turn(jj)  = part_abs_turn(jj1)
            part_select(jj)    = part_select(jj1)
            part_impact(jj)    = part_impact(jj1)
            part_indiv(jj)     = part_indiv(jj1)
            part_linteract(jj) = part_linteract(jj1)
            part_hit_before_pos(jj)  = part_hit_before_pos(jj1)
            part_hit_before_turn(jj) = part_hit_before_turn(jj1)
            secondary(jj)  = secondary(jj1)
            tertiary(jj)   = tertiary(jj1)
            other(jj)      = other(jj1)
            scatterhit(jj) = scatterhit(jj1)
            nabs_type(jj)  = nabs_type(jj1)
            !GRD HERE WE ADD A MARKER FOR THE PARTICLE FORMER NAME
            ipart(jj)      = ipart(jj1)
            flukaname(jj)  = flukaname(jj1)
#endif

            end do !do jj=j,lnapx-1

#ifdef FLUKA
            if (fluka_enable) then
              call fluka_lostpart(lnapx, j) ! Inform fluka
            end if
#endif

          end if !if(j.ne.lnapx) then

          lnapx=lnapx-1
        end if !if(llostp(j)) then
      end do !do j=napx,1,-1
      napx=lnapx
    end if !(.not.apflag)
end subroutine compactArrays

end module aperture
