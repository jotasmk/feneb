	program bandbuilder
!
!This program generates an initial set of replicas for NEB calculations in Amber .rst7 format,
!using only reactives and products restarts (and TS if possible)
!Original subroutine by N. Foglia 03/2018
!Adapted to amber restars by J. Semelak 09/2020
use readandget
use netcdf
implicit none
character(len=50) :: rcfile, pcfile, tsfile, prefix, chi, oname
integer :: nrestr, nrep, i, j, k, middlepoint, natoms, nscycle
logical ::  usets, per, velin, velout, onlytest, iddp, relaxd, equispaced, moved
double precision, dimension(3) :: BAND_slope
double precision, dimension(3) :: BAND_const
double precision, dimension(6):: boxinfo
integer, allocatable, dimension (:) :: mask
double precision, allocatable, dimension (:) :: energy
double precision, allocatable, dimension(:,:) :: rclas, selfdist, rref, profile
double precision, allocatable, dimension(:,:,:) :: rav, distmatrix, intdistmatrix, ravprev
double precision, allocatable, dimension(:,:,:) :: fav, tang, ftang, ftrue, fperp, fspring
double precision :: kspring, ftol, dontg, maxforceband, maxforceband2, stepl, steep_spring, steep_size
double precision :: energyreplica, maxenergy

!reads imputfile
call readinputbuilder(rcfile, pcfile, tsfile, prefix, nrestr, nrep, usets, per, velin, velout, rav, mask, iddp, onlytest)

if (onlytest) then
	allocate(rref(3,natoms))
	do i=1,nrep
		if (i .le. 9) write(chi,'(I1)') i
		if (i .gt. 9 .and. i .le. 99) write(chi,'(I2)') i
		if (i .gt. 99 .and. i .le. 999) write(chi,'(I3)') i
		oname = trim(prefix) // "_"
		oname = trim(oname) // trim(chi)
		oname = trim(oname) // ".rst7"
    ! call getfilenames(i,chi,infile,reffile,outfile,iname,rname,oname) !rname = NAME_r_i.rst7 ; i=replica
	  call getrefcoord(oname,nrestr,mask,natoms,rref,boxinfo,per,velin)
	  call getcoordextrema(rref,natoms,rav,nrestr,nrep,i,mask)
  end do
	allocate(selfdist(nrestr,nrep-1))
	call selfdistiniband(rav, nrep, nrestr, selfdist)

	open(unit=1111, file="selfdist.dat")
	do i=1,nrestr
		do j=1,nrep-1
			write(1111,'(2x, I6,2x, f20.10)') j, selfdist(i,j)
		end do
		write(1111,*)
	end do
STOP
end if

if (usets) then
	!reads middlepoint coordinates
	if (allocated(rclas)) deallocate(rclas)
	call getrefcoord(tsfile,nrestr,mask,natoms,rclas,boxinfo,per,velin)
	middlepoint=nrep+1
	middlepoint=middlepoint/2
	do i=1,nrestr
close(1001)
		rav(1:3,i,middlepoint)=rclas(1:3,mask(i))
	end do
else
	middlepoint=nrep
end if

!reads product complex coordinates
if (allocated(rclas)) deallocate(rclas)
call getrefcoord(pcfile,nrestr,mask,natoms,rclas,boxinfo,per,velin)

do i=1,nrestr
	rav(1:3,i,nrep)=rclas(1:3,mask(i))
end do

!reads reactant complex coordinates
if (allocated(rclas)) deallocate(rclas)
call getrefcoord(rcfile,nrestr,mask,natoms,rclas,boxinfo,per,velin)

do i=1,nrestr
	rav(1:3,i,1)=rclas(1:3,mask(i))
end do

!generate initial middleimages by linear interpolation
do i=1,nrestr
  BAND_slope(1:3)= rav(1:3,i,middlepoint)-rav(1:3,i,1)
  BAND_slope=BAND_slope/(dble(middlepoint) - 1.d0)
  BAND_const=rav(1:3,i,1)-BAND_slope(1:3)
  do k=1, middlepoint
    rav(1:3,i,k)=BAND_slope(1:3)*dble(k) + BAND_const(1:3)
  end do

!usign TS state case
  if (middlepoint .ne. nrep) then
    BAND_slope(1:3)= rav(1:3,i,nrep) - rav(1:3,i,middlepoint)
    BAND_slope=BAND_slope/(dble(nrep) - dble(middlepoint))
    BAND_const=rav(1:3,i,middlepoint) - dble(middlepoint)*BAND_slope(1:3)
    do k=middlepoint, nrep
      rav(1:3,i,k)=BAND_slope(1:3)*dble(k) + BAND_const(1:3)
    end do
  end if
end do

if (iddp) then

  allocate(distmatrix(nrestr,nrestr,nrep),intdistmatrix(nrestr,nrestr,nrep),energy(nrep))
	allocate(fav(3,nrestr,nrep),fspring(3,nrestr,nrep),ftrue(3,nrestr,nrep),fperp(3,nrestr,nrep),ftang(3,nrestr,nrep))
	allocate(tang(3,nrestr,nrep))
	allocate(profile(2,nrep-1))

	kspring=5000.d0
  ftol=0.d0
	dontg=0.d0
	relaxd=.false.
  nscycle=500.
  steep_size=1000d0
! TEST---------------------

call getdistmatrix(nrestr,nrep,distmatrix,rav)
open(unit=88881, file="INIdistmatrix.dat")
do i=1,nrestr
  do j=1,nrestr
    if (i.ne.j) then
		  do k=1,nrep
        write(88881,'(2x, I6,2x, f20.10)') k, distmatrix(i,j,k)
			end do
			write(88881,'(2x, I6,2x, f20.10)')
	  endif
  end do
end do
close(88881)

	do j=1,2500
		write(9999,*) "PASO", j
	  call getdistmatrix(nrestr,nrep,distmatrix,rav)
    if(j.eq.1) call getintdistmatrix(nrestr,nrep,distmatrix,intdistmatrix)
    call getenergyandforce(rav,nrestr,nrep,distmatrix,intdistmatrix,energy,maxenergy,fav)
	  call gettang(rav,tang,nrestr,nrep)
	  call getnebforce(rav,fav,tang,nrestr,nrep,kspring,maxforceband,ftol,relaxd,&
											ftrue,ftang,fperp,fspring,.true.,dontg)
		write(11111,*) j, maxenergy, maxforceband, steep_size
		write(*,*) j, maxenergy,maxforceband, steep_size
	  do i=2,nrep-1
      moved=.False.
		  do while (.not. moved)
		    ravprev=rav
		    call steep(rav,fperp,nrep,i,steep_size,maxforceband,nrestr,0.d0,stepl,0.d0,dontg)
		 	  moved=(energyreplica(rav,intdistmatrix,nrestr,nrep,i) .lt. maxenergy)
				! write(*,*) energyreplica(rav,intdistmatrix,nrestr,nrep,i)
		    if (.not. moved) then
          rav=ravprev
			    steep_size=steep_size*0.9d0
  		  end if
	  	end do
    end do
		do i=1,nrep
			write(22222,*) energy(i)
    end do
		write(22222,*)
		! write(*,*) j,steep_size

	equispaced=.False.
	k=1
	do while ((k .le. nscycle) .and. (.not. equispaced))
		call gettang(rav,tang,nrestr,nrep)
		call getnebforce(rav,fav,tang,nrestr,nrep,kspring,maxforceband2,0.d0,relaxd,&
										ftrue,ftang,fperp,fspring,.false.,dontg)
			do i=2,nrep-1
				call steep(rav,fspring,nrep,i,0.001d0,maxforceband2,nrestr,0.d0,stepl,0.d0,dontg)
			end do

		! write(9999,*) "Band max fspring: ",k, maxforceband2
	  ! write(9999,*) "-----------------------------------------------------------------"

		call getdistrightminusleft(rav, nrep, nrestr, equispaced)

		if ((k .eq. nscycle) .or. equispaced) then
			write(9999,*) "-----------------------------------------------------"
			write(9999,*) "Band max fspringLast: ", maxforceband
			write(9999,*) "Total spring steps: ", k
			write(9999,*) "Equispaced: ", equispaced
			write(9999,*) "-----------------------------------------------------"
		end if
		k=k+1
	  end do
	end do

	call getdistmatrix(nrestr,nrep,distmatrix,rav)
	open(unit=8888, file="distmatrix.dat")
	do i=1,nrestr
	  do j=1,nrestr
	    if (i.ne.j) then
			  do k=1,nrep
	        write(8888,'(2x, I6,2x, f20.10)') k, distmatrix(i,j,k)
				end do
				write(8888,'(2x, I6,2x, f20.10)')
		  endif
	  end do
	end do
	close(8888)
endif

! write output files

do i=1,nrep
			if (i .le. 9) write(chi,'(I1)') i
			if (i .gt. 9 .and. i .le. 99) write(chi,'(I2)') i
	    if (i .gt. 99 .and. i .le. 999) write(chi,'(I3)') i
			oname = trim(prefix) // "_"
  		oname = trim(oname) // trim(chi)
			oname = trim(oname) // ".rst7"
	    call writenewcoord(oname,rclas,boxinfo,natoms,nrestr,mask,per,velout,rav,nrep,i,onlytest)
end do

allocate(selfdist(nrestr,nrep-1))
call selfdistiniband(rav, nrep, nrestr, selfdist)

open(unit=1111, file="selfdist.dat")
do i=1,nrestr
	do j=1,nrep-1
		write(1111,'(2x, I6,2x, f20.10)') j, selfdist(i,j)
	end do
	write(1111,*)
end do
close(1111)

end program bandbuilder


subroutine getdistmatrix(nrestr,nrep,distmatrix,rav)
implicit none
integer :: i,j,k,nrestr,nrep
double precision, dimension (nrestr,nrestr,nrep) :: distmatrix
double precision, dimension (3,nrestr,nrep) :: rav

distmatrix=0.d0
do k=1, nrep
  do i=1,nrestr
	  do j=1,nrestr
      if (i.ne.j) then
	      distmatrix(i,j,k)=((rav(1,i,k)-rav(1,j,k))**2) + &
		                      ((rav(2,i,k)-rav(2,j,k))**2) + &
				      						((rav(3,i,k)-rav(3,j,k))**2)
		    distmatrix(i,j,k)=dsqrt(distmatrix(i,j,k))
		  endif
    end do
  end do
end do
end subroutine getdistmatrix

subroutine getintdistmatrix(nrestr,nrep,distmatrix,intdistmatrix)
implicit none
integer :: i,j,k,nrestr,nrep
double precision, dimension (nrestr,nrestr,nrep) :: distmatrix, intdistmatrix

intdistmatrix=0.d0
do k=1, nrep
	do i=1,nrestr
		do j=1,nrestr
			if (i.ne.j) then
				intdistmatrix(i,j,k)=distmatrix(i,j,1)+ &
														 dble(k-1)*(distmatrix(i,j,nrep)-distmatrix(i,j,1))/dble(nrep-1)

			endif
		end do
	end do
end do
! intdistmatrix=0.d0


end subroutine getintdistmatrix

subroutine  getenergyandforce(rav,nrestr,nrep,distmatrix,intdistmatrix,energy,maxenergy,fav)
implicit none
integer :: i,j,k,l,n,nrestr,nrep
double precision, dimension (nrestr,nrestr,nrep) :: distmatrix, intdistmatrix
double precision, dimension (nrep) :: energy
double precision, dimension (2,nrep-2) :: profile
double precision, dimension (3,nrestr,nrep) :: rav, fav
double precision, dimension (3,nrestr,nrep) :: favn
double precision :: dd,dij,fij,dx,dy,dz, D, energyreplica, maxenergy


maxenergy=energyreplica(rav,intdistmatrix,nrestr,nrep,1)
do k=1, nrep
  energy(k)=energyreplica(rav,intdistmatrix,nrestr,nrep,k)
	if (energy(k) .gt. maxenergy) maxenergy=energy(k)
end do

fav=0.d0
do k=1,nrep
  do i=1,nrestr-1
	  do j=i+1,nrestr
		  dd=(intdistmatrix(i,j,k)-distmatrix(i,j,k))
			dij=distmatrix(i,j,k)
			fij=(2.d0*dd/(dij**5))*(1.d0 + (2.d0*dd/dij))

			dx=(rav(1,i,k)-rav(1,j,k))
			dy=(rav(2,i,k)-rav(2,j,k))
			dz=(rav(3,i,k)-rav(3,j,k))

			fav(1,i,k)=fav(1,i,k)+fij*dx
			fav(2,i,k)=fav(2,i,k)+fij*dy
			fav(3,i,k)=fav(3,i,k)+fij*dz
			fav(1,j,k)=fav(1,j,k)-fij*dx
			fav(2,j,k)=fav(2,j,k)-fij*dy
			fav(3,j,k)=fav(3,j,k)-fij*dz


		end do
	end do
end do


end subroutine getenergyandforce

subroutine selfdistiniband(rav, nrep, nrestr, selfdist)
implicit none
double precision, dimension(3,nrestr,nrep), intent(in) :: rav
integer, intent(in) :: nrestr, nrep
double precision, dimension(nrestr,nrep-1), intent(out) :: selfdist
integer :: i,j,n

selfdist=0.d0
do n=1,nrep-1
  do i=1,nrestr
    do j=1,3
      selfdist(i,n)=selfdist(i,n)+(rav(j,i,n)-rav(j,i,n+1))**2
    end do
    selfdist(i,n)=dsqrt(selfdist(i,n))
  end do
end do
end subroutine selfdistiniband

function energyreplica(rav,intdistmatrix,nrestr,nrep,rep)
implicit none
double precision, dimension (nrestr,nrestr,nrep) :: distmatrix, intdistmatrix
double precision, dimension (3,nrestr,nrep) :: rav, fav
double precision :: energyreplica,dij,dd
integer :: nrestr,nrep,i,j,rep

call getdistmatrix(nrestr,nrep,distmatrix,rav)

	energyreplica=0.d0
		do i=1,nrestr-1
			do j=i+1,nrestr
	   			dd=(intdistmatrix(i,j,rep)-distmatrix(i,j,rep))
					dij=distmatrix(i,j,rep)
					energyreplica=energyreplica+(1.d0/(dij**4))*dd**2
			end do
		end do

end function energyreplica
